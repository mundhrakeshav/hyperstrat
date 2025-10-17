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
    address private constant WHYPE = address(0x5555555555555555555555555555555555555555);
    
    // Note: Do not assume a fixed "other" token; derive from pool at runtime
    uint8 private constant DEFAULT_PLUGIN_CONFIG =
        uint8(Plugins.BEFORE_SWAP_FLAG | Plugins.AFTER_SWAP_FLAG | Plugins.AFTER_INIT_FLAG | Plugins.DYNAMIC_FEE);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    IAlgebraPool public immutable pool; // The pool this plugin is attached to
    ISwapRouter public immutable swapRouter; // Swap router for token conversions
    IHyperStrategy public immutable hyperStrategy; // HyperStrategy contract
    

    uint256 public initTimestamp;
    uint256 public burnBps; // portion of plugin fees to burn (in TOTAL_BPS)
    bool private transient isPluginSwap; // flag to indicate if swap is being done by plugin

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

    event PluginFee(address indexed pool, uint256 feeAmount0, uint256 feeAmount1);
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

    /// @notice Handles plugin fee transfers from the pool.
    /// @param pluginFee0 Amount of fees accrued for side 0
    /// @param pluginFee1 Amount of fees accrued for side 1
    /// @return bytes4 Function selector to satisfy hook interface
    function handlePluginFee(uint256 pluginFee0, uint256 pluginFee1) external returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        emit PluginFee(address(pool), pluginFee0, pluginFee1);
        return this.handlePluginFee.selector;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               FEE LOGIC                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Withdraws all tokens: burns burnBps portion, sends remainder to owner.
    /// @dev Complex logic: burn WHYPE portion, burn strategy portion, swap remaining strategy to WHYPE, send all WHYPE.
    function withdraw(address to) external onlyOwner nonReentrant {
        address strategyToken = address(hyperStrategy);
        
        // Set flag to indicate plugin is performing swaps (no fees)
        isPluginSwap = true;
        
        // 1. Check total WHYPE Balance
        uint256 totalWHYPE = IERC20(WHYPE).balanceOf(address(this));
        
        // 2. Calculate Burnable amt (WHYPE portion to burn)
        uint256 burnableWHYPE = (totalWHYPE * burnBps) / TOTAL_BPS;
        
        // 3. Swap Burnable WHYPE to strategy token
        uint256 swappedStrategy = 0;
        if (burnableWHYPE > 0) {
            SafeTransferLib.safeApprove(WHYPE, address(swapRouter), burnableWHYPE);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: WHYPE,
                deployer: address(0),
                tokenOut: strategyToken,
                recipient: address(this),
                deadline: block.timestamp + 120,
                amountIn: burnableWHYPE,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            });
            swappedStrategy = swapRouter.exactInputSingle(params);
            emit BurnViaSwap(WHYPE, strategyToken, burnableWHYPE, swappedStrategy);
        }
        
        // 4. Check how much strategy token we have
        uint256 totalStrategy = IERC20(strategyToken).balanceOf(address(this));
        
        // 5. Calculate burnable strategy token
        uint256 burnableStrategy = (totalStrategy * burnBps) / TOTAL_BPS;
        
        // 6. Sum (Swapped strategy token in step 3 and 5) and burn it
        uint256 totalToBurn = swappedStrategy + burnableStrategy;
        if (totalToBurn > 0) {
            SafeTransferLib.safeTransfer(strategyToken, DEAD_ADDRESS, totalToBurn);
            emit Burn(strategyToken, totalToBurn);
        }
        
        // 7. Swap remaining strategy token to WHYPE
        uint256 remainingStrategy = totalStrategy - burnableStrategy;
        if (remainingStrategy > 0) {
            SafeTransferLib.safeApprove(strategyToken, address(swapRouter), remainingStrategy);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: strategyToken,
                deployer: address(0),
                tokenOut: WHYPE,
                recipient: address(this),
                deadline: block.timestamp + 120,
                amountIn: remainingStrategy,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            });
            swapRouter.exactInputSingle(params);
        }
        
        // Reset flag after swaps are complete
        isPluginSwap = false;
        
        // 8. Transfer all WHYPE
        uint256 finalWHYPE = IERC20(WHYPE).balanceOf(address(this));
        if (finalWHYPE > 0) {
            SafeTransferLib.safeTransfer(WHYPE, to, finalWHYPE);
            emit Withdraw(WHYPE, to, finalWHYPE);
        }
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
        address sender,
        address recipient,
        bool zeroToOne, /*zeroToOne*/
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        bool, /*withPaymentInAdvance*/
        bytes calldata /*data*/
    ) external view override returns (bytes4 selector, uint24 feeOverride, uint24 pluginFee) {
        if (msg.sender != address(pool)) revert PoolMismatch();

        // If plugin is performing the swap, set all fees to 0
        if (isPluginSwap) {
            return (this.beforeSwap.selector, 0, 0);
        }

        // Dynamic fee logic:
        // - "Buy" direction starts at 99% and linearly decays to 10% over 1 hour
        // - "Sell" direction is a constant 10%
        // Convention: zeroToOne = WHYPE -> strategy (buy), !zeroToOne = strategy -> WHYPE (sell)
        uint24 feeBips;
        bool isBuy = zeroToOne; // WHYPE -> strategy is a buy
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
        address recipient,
        bool zeroToOne,
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        int256, /*amount0*/
        int256, /*amount1*/
        bytes calldata /*data*/
    ) external override returns (bytes4) {
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




}
