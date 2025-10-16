// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import "./HyperInterfaces.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {Plugins} from "@cryptoalgebra/integral-core/contracts/libraries/Plugins.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraPlugin} from "@cryptoalgebra/integral-core/contracts/interfaces/plugin/IAlgebraPlugin.sol";

import {console} from "forge-std/console.sol";
/// @title Hyper Strategy Plugin Hooks - https://hyperstr.xyz
contract HyperPlugin is IAlgebraPlugin, ReentrancyGuard {
    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CONSTANTS                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    uint256 private constant TOTAL_BIPS = 1_000_000;
    uint256 private constant DEFAULT_FEE = 100_000; // 10%
    uint256 private constant STARTING_BUY_FEE = 990_000; // 99%
    uint8 private constant DEFAULT_PLUGIN_CONFIG = uint8(Plugins.BEFORE_SWAP_FLAG | Plugins.AFTER_SWAP_FLAG | Plugins.AFTER_INIT_FLAG | Plugins.DYNAMIC_FEE);

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               STATE VARIABLES                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    IHyperFactory public immutable factory; // Factory managing HyperStrategy contracts and controls
    IAlgebraPool public immutable pool; // The pool this plugin is attached to
    ISwapRouter public immutable swapRouter; // Swap router for token conversions
    IHyperStrategy public immutable hyperStrategy; // HyperStrategy contract

    address public feeAddress; // Address receiving fees
    uint256 public initTimestamp;
    bool public strategyIsToken0;

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM ERRORS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    error NotHyperStrategy();
    error NotHyperStrategyFactoryOwner();
    error PoolMismatch();
    error NeedAdditionalData();

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               CUSTOM EVENTS                                 */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    event PluginFee(address indexed pool, address indexed sender, uint256 feeAmount0, uint256 feeAmount1);
    event Trade(address indexed hyperStrategy, uint160 sqrtPriceX96, int256 amount0, int256 amount1);

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
        IHyperStrategy _hyperStrategy,
        address _feeAddress
    ) {
        pool = _pool;
        factory = _factory;
        swapRouter = _swapRouter;
        hyperStrategy = _hyperStrategy;
        feeAddress = _feeAddress;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               ADMIN FUNCTIONS                               */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /// @notice Updates the fee address for receiving protocol fees
    /// @param _feeAddress New address to receive fees
    function updateFeeAddress(address _feeAddress) external {
        if (msg.sender != factory.owner()) {
            revert NotHyperStrategyFactoryOwner();
        }
        feeAddress = _feeAddress;
    }

    /// @notice Handle plugin fee transfer from Algebra pool
    /// @param pluginFee0 Fee0 amount transferred to plugin
    /// @param pluginFee1 Fee1 amount transferred to plugin
    /// @return bytes4 The function selector
    function handlePluginFee(uint256 pluginFee0, uint256 pluginFee1) external returns (bytes4) {
        // Only the pool can call this function
        if (msg.sender != address(pool)) revert PoolMismatch();
        console.log("pluginFee0: ", pluginFee0);
        console.log("pluginFee1: ", pluginFee1);
        return this.handlePluginFee.selector;
    }

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               FEE LOGIC                                     */
    /* ═══════════════════════════════════════════════════════════════════════════ */

    /* ═══════════════════════════════════════════════════════════════════════════ */
    /*                               UTILITY FUNCTIONS                             */
    /* ═══════════════════════════════════════════════════════════════════════════ */

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
    ) external override returns (bytes4 selector, uint24 pluginFee) {
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
    ) external override returns (bytes4) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        return this.afterModifyPosition.selector;
    }

    function beforeSwap(
        address, /*sender*/
        address, /*recipient*/
        bool zeroToOne, /*zeroToOne*/
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        bool, /*withPaymentInAdvance*/
        bytes calldata /*data*/
    ) external override returns (bytes4 selector, uint24 feeOverride, uint24 pluginFee) {
        if (msg.sender != address(pool)) revert PoolMismatch();
        // Mark mid-swap to restrict router if needed
        if (factory.routerRestrict()) {
            hyperStrategy.setMidSwap(false);
        }

        // Dynamic fee logic:
        // - "Buy" direction starts at 99% and linearly decays to 10% over 1 hour
        // - "Sell" direction is a constant 10%
        // Convention used: zeroToOne indicates token0 -> token1 swap which we treat as a "buy" of token1
        uint24 feeBips;
        bool isBuy = strategyIsToken0 ? !zeroToOne : zeroToOne;
        if (isBuy) {
            // Buy path: decay from STARTING_BUY_FEE to DEFAULT_FEE over 3600 seconds
            uint256 elapsed = block.timestamp - initTimestamp;
            if (elapsed >= 3600) {
                feeBips = uint24(DEFAULT_FEE);
            } else {
                uint256 start = STARTING_BUY_FEE;
                uint256 end_ = DEFAULT_FEE;
                uint256 decayed = start - ((start - end_) * elapsed) / 3600;
                feeBips = uint24(decayed);
            }
        } else {
            // Sell path: constant DEFAULT_FEE
            feeBips = uint24(DEFAULT_FEE);
        }

        // No feeOverride, only pluginFee is applied
        return (this.beforeSwap.selector, 0, feeBips);
    }

    function afterSwap(
        address sender,
        address, /*recipient*/
        bool zeroToOne,
        int256, /*amountRequired*/
        uint160, /*limitSqrtPrice*/
        int256 amount0,
        int256 amount1,
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
    ) external override returns (bytes4) {
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
    ) external override returns (bytes4) {
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
