// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {Plugins} from "@cryptoalgebra/integral-core/contracts/libraries/Plugins.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraPlugin} from "@cryptoalgebra/integral-core/contracts/interfaces/plugin/IAlgebraPlugin.sol";

import {IHyperStrategy} from "src/interfaces/IHyperStrategy.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @title Hyper Strategy Plugin Hooks - https://hyperstr.xyz

contract HyperPlugin is IAlgebraPlugin, ReentrancyGuard, Ownable {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CONSTANTS                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    uint256 private constant TOTAL_BPS = 1_000_000;
    uint256 private constant DEFAULT_TRADE_FEE = 100_000; // 10%
    uint256 private constant STARTING_BUY_FEE = 990_000; // 99%

    address private constant DEAD_ADDRESS = address(0xdEaD);
    address public constant WHYPE = address(0x5555555555555555555555555555555555555555);
    uint8 private constant DEFAULT_PLUGIN_CONFIG =
        uint8(Plugins.BEFORE_SWAP_FLAG | Plugins.AFTER_SWAP_FLAG | Plugins.AFTER_INIT_FLAG | Plugins.DYNAMIC_FEE);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    IAlgebraPool public immutable pool; // The pool this plugin is attached to
    ISwapRouter public immutable swapRouter; // Swap router for token conversions
    IHyperStrategy public immutable hyperStrategy; // HyperStrategy contract

    uint256 public initTimestamp;
    bool public strategyIsToken0;
    uint256 public burnBps; // portion of plugin fees to burn (in TOTAL_BPS)


    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM ERRORS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error NotHyperStrategy();
    error NotHyperStrategyFactoryOwner();
    error PoolMismatch();
    error NeedAdditionalData();
    error InvalidAddress();
    error InvalidBurnBps();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM EVENTS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event PluginFee(address indexed pool, address indexed sender, uint256 feeAmount0, uint256 feeAmount1);
    event Trade(address indexed hyperStrategy, uint160 sqrtPriceX96, int256 amount0, int256 amount1);
    event FeesAccrued(address indexed token, uint256 withdrawableIncrement, uint256 burnableIncrement);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event Burn(address indexed token, uint256 amount);
    event BurnViaSwap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CONSTRUCTOR                                   */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Initializes the plugin with required dependencies.
    /// @param _pool The Algebra pool this plugin is attached to
    /// @param _swapRouter The Algebra swap router
    /// @param _hyperStrategy The HyperStrategy token contract
    /// @param _owner The owner of the contract
    constructor(IAlgebraPool _pool, ISwapRouter _swapRouter, IHyperStrategy _hyperStrategy, address _owner) {
        pool = _pool;
        swapRouter = _swapRouter;
        hyperStrategy = _hyperStrategy;
        burnBps = 800_000; // 80% burn by default
        _initializeOwner(_owner);
    }

    function _guardInitializeOwner() internal pure override returns (bool guard) {
        return true;
    }
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               ADMIN FUNCTIONS                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Sets the percentage of fees to burn, in parts-per-million (TOTAL_BPS).
    /// @param _burnBps Burn share in ppm, where 1_000_000 = 100%
    function setBurnBps(uint256 _burnBps) external onlyOwner {
        if (_burnBps > TOTAL_BPS) revert InvalidBurnBps();
        burnBps = _burnBps;
    }

    /// @notice Handles plugin fee transfers from the pool and immediately burns the burn-share.
    /// @dev If the incoming token is the strategy token, it is burned directly. Otherwise it is
    ///      swapped from WHYPE to the strategy token and burned. The non-burn remainder stays as
    ///      this contract's balance and is withdrawable by the owner.
    /// @param pluginFee0 Amount of fees accrued for side 0
    /// @param pluginFee1 Amount of fees accrued for side 1
    /// @return bytes4 Function selector to satisfy hook interface
    function handlePluginFee(uint256 pluginFee0, uint256 pluginFee1) external returns (bytes4) {
        // Only the pool can call this function
        if (msg.sender != address(pool)) revert PoolMismatch();

        // Canonical tokens: strategy token and WHYPE (the other side)
        address strategyToken = address(hyperStrategy);

        if (pluginFee0 > 0) {
            uint256 burnAmount = (pluginFee0 * burnBps) / TOTAL_BPS;
            // Remainder stays in contract balance for owner withdrawal
            if (burnAmount > 0) {
                if (strategyIsToken0) {
                    // Direct burn if strategy token
                    SafeTransferLib.safeTransfer(strategyToken, DEAD_ADDRESS, burnAmount);
                    emit Burn(strategyToken, burnAmount);
                } else {
                    // Swap WHYPE to strategy token and burn
                    SafeTransferLib.safeApprove(WHYPE, address(swapRouter), burnAmount);
                    ISwapRouter.ExactInputSingleParams memory params0 = ISwapRouter.ExactInputSingleParams({
                        tokenIn: WHYPE,
                        deployer: address(0),
                        tokenOut: strategyToken,
                        recipient: DEAD_ADDRESS,
                        deadline: block.timestamp + 300,
                        amountIn: burnAmount,
                        amountOutMinimum: 0,
                        limitSqrtPrice: 0
                    });
                    uint256 amountOut0 = swapRouter.exactInputSingle(params0);
                    emit BurnViaSwap(WHYPE, strategyToken, burnAmount, amountOut0);
                }
            }
            emit FeesAccrued(strategyIsToken0 ? strategyToken : WHYPE, pluginFee0 - burnAmount, burnAmount);
        }

        if (pluginFee1 > 0) {
            uint256 burnAmount1 = (pluginFee1 * burnBps) / TOTAL_BPS;
            // Remainder stays in contract balance for owner withdrawal
            if (burnAmount1 > 0) {
                if (!strategyIsToken0) {
                    SafeTransferLib.safeTransfer(strategyToken, DEAD_ADDRESS, burnAmount1);
                    emit Burn(strategyToken, burnAmount1);
                } else {
                    SafeTransferLib.safeApprove(WHYPE, address(swapRouter), burnAmount1);
                    ISwapRouter.ExactInputSingleParams memory params1 = ISwapRouter.ExactInputSingleParams({
                        tokenIn: WHYPE,
                        deployer: address(0),
                        tokenOut: strategyToken,
                        recipient: DEAD_ADDRESS,
                        deadline: block.timestamp + 300,
                        amountIn: burnAmount1,
                        amountOutMinimum: 0,
                        limitSqrtPrice: 0
                    });
                    uint256 amountOut1 = swapRouter.exactInputSingle(params1);
                    emit BurnViaSwap(WHYPE, strategyToken, burnAmount1, amountOut1);
                }
            }
            emit FeesAccrued(strategyIsToken0 ? WHYPE : strategyToken, pluginFee1 - burnAmount1, burnAmount1);
        }

        emit PluginFee(address(pool), msg.sender, pluginFee0, pluginFee1);
        return this.handlePluginFee.selector;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               FEE LOGIC                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Withdraws fees held by this contract.
    /// @dev Only `address(hyperStrategy)` and `WHYPE` are valid tokens here.
    /// @param token ERC20 token to withdraw (strategy token or WHYPE)
    /// @param amount Amount to withdraw (capped to contract balance)
    /// @param to Recipient address
    function withdraw(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        // Only strategy token or WHYPE are valid
        if (token != address(hyperStrategy) && token != WHYPE) revert InvalidAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) amount = balance;
        if (amount == 0) return;
        SafeTransferLib.safeTransfer(token, to, amount);
        emit Withdraw(token, to, amount);
    }
    /// @notice Allows the contract to receive HYPE
    receive() external payable {}

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               ALGEBRA HOOKS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    function beforeInitialize(
        address,
        /*sender*/
        uint160 /*sqrtPriceX96*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();

        pool.setPluginConfig(uint8(DEFAULT_PLUGIN_CONFIG));

        return this.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        /*sender*/
        uint160,
        /*sqrtPriceX96*/
        int24 /*tick*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        strategyIsToken0 = (pool.token0() == address(hyperStrategy));
        initTimestamp = block.timestamp;
        return this.afterInitialize.selector;
    }

    function beforeModifyPosition(
        address, /*sender*/
        address, /*recipient*/
        int24, /*bottomTick*/
        int24, /*topTick*/
        int128, /*desiredLiquidityDelta*/
        bytes calldata /*data*/
    ) external view override returns (bytes4 selector, uint24 pluginFee) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return (this.beforeModifyPosition.selector, 0);
    }

    function afterModifyPosition(
        address, /*sender*/
        address, /*recipient*/
        int24, /*bottomTick*/
        int24, /*topTick*/
        int128, /*desiredLiquidityDelta*/
        uint256, /*amount0*/
        uint256, /*amount1*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterModifyPosition.selector;
    }

    function beforeSwap(
        address, /* sender */
        address recipient,
        bool zeroToOne, /*zeroToOne*/
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        bool, /*withPaymentInAdvance*/
        bytes calldata /*data*/
    ) external view override returns (bytes4 selector, uint24 feeOverride, uint24 pluginFee) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        if (recipient == address(hyperStrategy)) return (this.beforeSwap.selector, 0, 0);

        // Dynamic fee logic:
        // - "Buy" direction starts at 99% and linearly decays to 10% over 1 hour
        // - "Sell" direction is a constant 10%
        // Convention used: zeroToOne indicates token0 -> token1 swap which we treat as a "buy" of token1
        uint24 feeBips;
        bool isBuy = strategyIsToken0 ? !zeroToOne : zeroToOne;
        if (isBuy) {
            // Buy path: decay from STARTING_BUY_FEE to DEFAULT_TRADE_FEE over 3600 seconds
            uint256 elapsed = block.timestamp - initTimestamp;
            if (elapsed >= 3600) {
                feeBips = uint24(DEFAULT_TRADE_FEE);
            } else {
                uint256 start = STARTING_BUY_FEE;
                uint256 end_ = DEFAULT_TRADE_FEE;
                uint256 decayed = start - ((start - end_) * elapsed) / 3600;
                feeBips = uint24(decayed);
            }
        } else {
            // Sell path: constant DEFAULT_TRADE_FEE
            feeBips = uint24(DEFAULT_TRADE_FEE);
        }

        // No feeOverride, only pluginFee is applied
        return (this.beforeSwap.selector, 0, feeBips);
    }

    function afterSwap(
        address, /*sender*/
        address, /*recipient*/
        bool, /*zeroToOne*/
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        int256, /*amount0*/
        int256, /*amount1*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterSwap.selector;
    }

    function beforeFlash(
        address, /*sender*/
        address, /*recipient*/
        uint256, /*amount0*/
        uint256, /*amount1*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.beforeFlash.selector;
    }

    function afterFlash(
        address, /*sender*/
        address, /*recipient*/
        uint256, /*amount0*/
        uint256, /*amount1*/
        uint256, /*paid0*/
        uint256, /*paid1*/
        bytes calldata /*data*/
    ) external view override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterFlash.selector;
    }

    function defaultPluginConfig() external pure override returns (uint8) {
        return DEFAULT_PLUGIN_CONFIG;
    }

    function getCurrentFee() external pure returns (uint16) {
        revert NeedAdditionalData();
    }
}
