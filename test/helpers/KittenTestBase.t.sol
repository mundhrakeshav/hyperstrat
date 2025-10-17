// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IAlgebraFactory} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraFactory.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from
    "@cryptoalgebra/integral-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IQuoterV2} from "@cryptoalgebra/integral-periphery/contracts/interfaces/IQuoterV2.sol";
import {IAlgebraPlugin} from "@cryptoalgebra/integral-core/contracts/interfaces/plugin/IAlgebraPlugin.sol";
import {HyperPlugin} from "src/HyperPlugin.sol";
import {IHyperStrategy} from "src/interfaces/IHyperStrategy.sol";
import {HyperStrategy} from "src/HyperStrategy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

interface RBAC {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function grantRole(bytes32 role, address account) external;
}

/// @notice Shared test base providing KittenSwap env, token/pool fixture and helpers
abstract contract KittenTestBase is Test {
    // KittenSwap deployment addresses on the target network
    IAlgebraFactory internal constant KITTEN_SWAP_FACTORY = IAlgebraFactory(0x5f95E92c338e6453111Fc55ee66D4AafccE661A7);
    ISwapRouter internal constant KITTEN_SWAP_ROUTER = ISwapRouter(0x4e73E421480a7E0C24fB3c11019254edE194f736);
    IQuoterV2 internal constant KITTEN_QUOTER = IQuoterV2(0xc58874216AFe47779ADED27B8AAd77E8Bd6eBEBb);
    INonfungiblePositionManager internal constant KITTEN_NFT_MANAGER =
        INonfungiblePositionManager(0x9ea4459c8DefBF561495d95414b9CF1E2242a3E2);
    address internal constant HYPER_COLLECTION = 0x9125E2d6827a00B0F8330D6ef7BEF07730Bac685;
    address internal constant DEAD_ADDRESS = address(0xdEaD);
    address internal constant ZERO_ADDRESS = address(0);
    address internal constant WHYPE = address(0x5555555555555555555555555555555555555555);

    bytes32 internal constant DEFAULT_ADMIN_ROLE =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    address internal immutable DEFAULT_ADMIN_ROLE_KITTEN_ALGEBRA_FACTORY;

    // Common actors and state
    address internal poolAdmin = makeAddr("POOLS_ADMINISTRATOR_ROLE_ALGEBRA_FACTORY");
    address internal feeAddress = makeAddr("FEE_ADDRESS");

    IAlgebraPool internal pool;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address payable internal hyperStrategy;

    constructor() {
        // Discover default admin of Algebra factory to grant required roles for custom pool deploys
        DEFAULT_ADMIN_ROLE_KITTEN_ALGEBRA_FACTORY =
            RBAC(address(KITTEN_SWAP_FACTORY)).getRoleMember(DEFAULT_ADMIN_ROLE, 0);

        // grant roles to poolAdmin and customPoolDeployer
        vm.startPrank(DEFAULT_ADMIN_ROLE_KITTEN_ALGEBRA_FACTORY);
        RBAC(address(KITTEN_SWAP_FACTORY)).grantRole(
            IAlgebraFactory(KITTEN_SWAP_FACTORY).POOLS_ADMINISTRATOR_ROLE(), poolAdmin
        );
        RBAC(address(KITTEN_SWAP_FACTORY)).grantRole(
            IAlgebraFactory(KITTEN_SWAP_FACTORY).CUSTOM_POOL_DEPLOYER(), address(this)
        );
        vm.stopPrank();
    }

    /// @notice Deploy tokens and HyperStrategy, then create pool and seed liquidity
    function setUpFixture() internal {
        token0 = MockERC20(WHYPE);
        deal(address(token0), address(this), 1e9 * 1e18);
        hyperStrategy =
            payable(address(new HyperStrategy("Hypurr", "HYPE", address(this), KITTEN_SWAP_ROUTER, HYPER_COLLECTION)));
        token1 = MockERC20(address(hyperStrategy));

        // Ensure token ordering matches pool expectations
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        deployAndInitializePool();

        IHyperStrategy(hyperStrategy).setTransferAddressWhitelist(address(KITTEN_SWAP_ROUTER), true);
        IHyperStrategy(hyperStrategy).setTransferAddressWhitelist(address(pool.plugin()), true);
        IHyperStrategy(hyperStrategy).setTransferAddressWhitelist(address(pool), true);
        IHyperStrategy(hyperStrategy).setTransferAddressWhitelist(address(DEAD_ADDRESS), true);
        
        mintLiquidity();
    }

    function deployAndInitializePool() internal {
        token0.approve(address(KITTEN_SWAP_FACTORY), type(uint256).max);
        token1.approve(address(KITTEN_SWAP_FACTORY), type(uint256).max);

        pool = IAlgebraPool(
            KITTEN_SWAP_FACTORY.createPool(address(token0), address(token1), "")
        );
        console.log("pool deployed at: ", address(pool), pool.plugin());

        // Deploy our custom HyperPlugin and set it as the pool's plugin BEFORE initialize
        HyperPlugin plugin = new HyperPlugin(
            pool,
            KITTEN_SWAP_ROUTER,
            IHyperStrategy(payable(hyperStrategy)),
            address(this)
        );

        // setPlugin is permissioned to POOLS_ADMINISTRATOR_ROLE -> use the granted role holder
        vm.prank(poolAdmin);
        pool.setPlugin(address(plugin));

        // Now initialize so plugin hooks run and strategyIsToken0 is set
        pool.initialize(79228162514264337593543950336);
    }

    function mintLiquidity() internal {
        token0.approve(address(KITTEN_NFT_MANAGER), type(uint256).max);
        token1.approve(address(KITTEN_NFT_MANAGER), type(uint256).max);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            deployer: ZERO_ADDRESS,
            tickLower: -887220,
            tickUpper: 887220,
            amount0Desired: 1e22,
            amount1Desired: 1e22,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 150
        });

        KITTEN_NFT_MANAGER.mint(mintParams);
    }

    /// @notice Generic swap helper to support different token pairs and amounts
    /// @param _tokenIn The token being sold
    /// @param _tokenOut The token being bought
    /// @param amountIn Exact amount of `_tokenIn` to swap
    /// @param minOut Minimum acceptable amount of `_tokenOut` (slippage protection)
    function swapExact(address _tokenIn, address _tokenOut, uint256 amountIn, uint256 minOut)
        internal
        returns (uint256 amountOut)
    {
        // Approve only the input token
        MockERC20(_tokenIn).approve(address(KITTEN_SWAP_ROUTER), type(uint256).max);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            deployer: ZERO_ADDRESS,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            limitSqrtPrice: 0
        });

        amountOut = KITTEN_SWAP_ROUTER.exactInputSingle(params);
    }
}
