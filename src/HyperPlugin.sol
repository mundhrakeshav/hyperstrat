// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import "./HyperInterfaces.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraPlugin} from "@cryptoalgebra/integral-core/contracts/interfaces/plugin/IAlgebraPlugin.sol";

/// @title Hyper Strategy Plugin Hooks - https://hyperstr.xyz
contract HyperPlugin is IAlgebraPlugin, ReentrancyGuard {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CONSTANTS                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    uint128 private constant TOTAL_BIPS = 10000;
    uint128 private constant DEFAULT_FEE = 1000; // 10%
    uint128 private constant STARTING_BUY_FEE = 9500; // 95%

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    IHyperFactory public immutable factory; // Factory managing HyperStrategy contracts and controls
    IAlgebraPool public immutable pool; // The pool this plugin is attached to
    ISwapRouter public immutable swapRouter; // Swap router for token conversions
    address public feeAddress; // Address receiving 20% of fees (protocol)

    mapping(address => uint256) public deploymentBlock;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM ERRORS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error NotHyperStrategy();
    error NotHyperStrategyFactoryOwner();
    error PoolMismatch();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM EVENTS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event PluginFee(
        address indexed pool,
        address indexed sender,
        uint256 feeAmount0,
        uint256 feeAmount1
    );
    event Trade(
        address indexed hyperStrategy,
        uint160 sqrtPriceX96,
        int256 amount0,
        int256 amount1
    );

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CONSTRUCTOR                                   */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Constructor initializes the plugin with required dependencies
    /// @param _pool The GLiquid pool this plugin is attached to
    /// @param _factory The HyperFactory contract
    /// @param _swapRouter The GLiquid swap router
    /// @param _feeAddress Address to send protocol fees (20%)
    constructor(
        IAlgebraPool _pool,
        IHyperFactory _factory,
        ISwapRouter _swapRouter,
        address _feeAddress
    ) {
        pool = _pool;
        factory = _factory;
        swapRouter = _swapRouter;
        feeAddress = _feeAddress;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               ADMIN FUNCTIONS                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Updates the fee address for receiving protocol fees
    /// @param _feeAddress New address to receive fees
    function updateFeeAddress(address _feeAddress) external {
        if (msg.sender != factory.owner())
            revert NotHyperStrategyFactoryOwner();
        feeAddress = _feeAddress;
    }

    /// @notice Handle plugin fee transfer from Algebra pool
    /// @param pluginFee0 Fee0 amount transferred to plugin
    /// @param pluginFee1 Fee1 amount transferred to plugin
    /// @return bytes4 The function selector
    function handlePluginFee(
        uint256 pluginFee0,
        uint256 pluginFee1
    ) external returns (bytes4) {
        // Only the pool can call this function
        if (msg.sender != address(pool)) revert PoolMismatch();

        // Process fees if any were received
        if (pluginFee0 > 0 || pluginFee1 > 0) {
            address collection = pool.token1();

            // Convert token1 fees to HYPE if needed
            if (pluginFee1 > 0) {
                uint256 hypeAmount = _swapToHype(pluginFee1);
                _processFees(collection, hypeAmount);
            }

            // Process HYPE fees directly
            if (pluginFee0 > 0) {
                _processFees(collection, pluginFee0);
            }
        }

        return this.handlePluginFee.selector;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               FEE LOGIC                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Process fees directly - distributes immediately
    /// @param collection The collection address
    /// @param feeAmount Amount of HYPE fees to distribute
    function _processFees(address collection, uint256 feeAmount) internal {
        if (feeAmount == 0) return;

        // Calculate 80% for the specific HyperStrategy and 20% for team
        uint256 depositAmount = (feeAmount * 80) / 100;
        uint256 teamAmount = feeAmount - depositAmount;

        // Deposit fees into HyperStrategy collection
        IHyperStrategy(collection).addFees{value: depositAmount}();

        // Send 20% to protocol fee address
        SafeTransferLib.forceSafeTransferETH(feeAddress, teamAmount);
    }

    /// @notice Calculates current fee based on deployment block and direction
    /// @param collection The collection address
    /// @param isBuying Whether this is a buy transaction
    /// @return Current fee in basis points
    function calculateFee(
        address collection,
        bool isBuying
    ) public view returns (uint128) {
        if (!isBuying) return DEFAULT_FEE;
        // Note: HyperFactory doesn't have deployerBuying, so we'll skip this check for now
        // TODO: Implement proper deployer buying logic

        uint256 deployedAt = deploymentBlock[collection];
        if (deployedAt == 0) return DEFAULT_FEE;

        uint256 blocksPassed = block.number - deployedAt;
        uint256 feeReductions = (blocksPassed / 5) * 100; // bips to subtract

        uint256 maxReducible = STARTING_BUY_FEE - DEFAULT_FEE;
        if (feeReductions >= maxReducible) return DEFAULT_FEE;

        return uint128(STARTING_BUY_FEE - feeReductions);
    }


    /// @notice Internal function to process swap fees and emit events
    function _processSwapFees(
        address sender,
        address poolAddress,
        bool zeroToOne,
        int256 amount0,
        int256 amount1
    ) internal {
        address collection = pool.token1();

        // Calculate fee based on swap amount
        uint256 swapAmount = zeroToOne
            ? (amount0 < 0 ? uint256(-amount0) : uint256(amount0))
            : (amount1 < 0 ? uint256(-amount1) : uint256(amount1));

        // Calculate and process fee
        uint128 currentFee = calculateFee(collection, zeroToOne);
        uint256 feeAmount = (swapAmount * currentFee) / TOTAL_BIPS;

        if (feeAmount > 0) {
            // For Algebra protocol, we need to collect fees differently
            // The plugin receives fees through handlePluginFee callback
            // We'll emit the fee event but actual collection happens elsewhere
            emit PluginFee(poolAddress, sender, feeAmount, 0);
        }

        // Get current price and emit trade event
        (uint160 sqrtPriceX96, , , , , ) = pool.globalState();
        emit Trade(collection, sqrtPriceX96, amount0, amount1);

        // Set midSwap to false (use pool.token1() which is the HyperStrategy token)
        if (factory.routerRestrict()) {
            IHyperStrategy(pool.token1()).setMidSwap(false);
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               UTILITY FUNCTIONS                             */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Swaps collection tokens to HYPE using the swap router
    /// @param amount The amount of collection tokens to swap
    /// @return The amount of HYPE received from the swap
    function _swapToHype(uint256 amount) internal returns (uint256) {
        uint256 hypeBefore = address(this).balance;

        // Get pool tokens
        address token0 = pool.token0();
        address token1 = pool.token1();

        // Determine which token is the strategy token (HYPE is token0)
        address strategyToken = (token0 == address(0)) ? token1 : token0;

        // Approve swap router to spend strategy tokens
        IERC20(strategyToken).approve(address(swapRouter), amount);

        // Prepare swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: strategyToken,
                deployer: address(0), // Standard pool
                tokenOut: address(0), // Native HYPE
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0, // No slippage protection
                limitSqrtPrice: 0 // No price limit
            });

        // Execute swap: strategy token -> HYPE
        swapRouter.exactInputSingle(params);

        uint256 hypeAfter = address(this).balance;
        return hypeAfter - hypeBefore;
    }

    /// @notice Allows the contract to receive HYPE
    receive() external payable {}

    function defaultPluginConfig() external pure override returns (uint8) {
        // By default, don't enable any special hooks or dynamic fee logic (all bits off)
        return 0;
    }
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               ALGEBRA HOOKS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */


    function beforeInitialize(
        address /*sender*/,
        uint160 /*sqrtPriceX96*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // No-op for now
        return this.beforeInitialize.selector;
    }

    function afterInitialize(
        address /*sender*/,
        uint160 /*sqrtPriceX96*/,
        int24 /*tick*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // Record deployment block for fee schedule if not set
        address collection = pool.token1();
        if (deploymentBlock[collection] == 0) {
            deploymentBlock[collection] = block.number;
        }
        return this.afterInitialize.selector;
    }

    function beforeModifyPosition(
        address /*sender*/,
        address /*recipient*/,
        int24 /*bottomTick*/,
        int24 /*topTick*/,
        int128 /*desiredLiquidityDelta*/,
        bytes calldata /*data*/
    ) external override returns (bytes4 selector, uint24 pluginFee) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // No additional fees for position modifications
        return (this.beforeModifyPosition.selector, 0);
    }

    function afterModifyPosition(
        address /*sender*/,
        address /*recipient*/,
        int24 /*bottomTick*/,
        int24 /*topTick*/,
        int128 /*desiredLiquidityDelta*/,
        uint256 /*amount0*/,
        uint256 /*amount1*/,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterModifyPosition.selector;
    }

    function beforeSwap(
        address /*sender*/,
        address /*recipient*/,
        bool /*zeroToOne*/,
        int256 /*amountRequired*/,
        uint160 /*limitSqrtPrice*/,
        bool /*withPaymentInAdvance*/,
        bytes calldata /*data*/
    )
        external
        override
        returns (bytes4 selector, uint24 feeOverride, uint24 pluginFee)
    {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // Mark mid-swap to restrict router if needed
        if (factory.routerRestrict()) {
            IHyperStrategy(pool.token1()).setMidSwap(true);
        }
        // No fee override and no immediate plugin fee taken in beforeSwap
        return (this.beforeSwap.selector, 0, 0);
    }

    function afterSwap(
        address sender,
        address /*recipient*/,
        bool zeroToOne,
        int256 /*amountRequired*/,
        uint160 /*limitSqrtPrice*/,
        int256 amount0,
        int256 amount1,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // Process internal accounting/events; actual fee transfer occurs via handlePluginFee
        _processSwapFees(sender, address(pool), zeroToOne, amount0, amount1);
        return this.afterSwap.selector;
    }

    function beforeFlash(
        address /*sender*/,
        address /*recipient*/,
        uint256 /*amount0*/,
        uint256 /*amount1*/,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.beforeFlash.selector;
    }

    function afterFlash(
        address /*sender*/,
        address /*recipient*/,
        uint256 /*amount0*/,
        uint256 /*amount1*/,
        uint256 /*paid0*/,
        uint256 /*paid1*/,
        bytes calldata /*data*/
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterFlash.selector;
    }
}
