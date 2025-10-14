// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {console} from "forge-std/console.sol";
import {IAlgebraFactory} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraFactory.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from
    "@cryptoalgebra/integral-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IQuoterV2} from "@cryptoalgebra/integral-periphery/contracts/interfaces/IQuoterV2.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {IAlgebraPlugin} from "@cryptoalgebra/integral-core/contracts/interfaces/plugin/IAlgebraPlugin.sol";
import {HyperPlugin} from "src/HyperPlugin.sol";
import {IHyperFactory} from "src/HyperInterfaces.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

interface RBAC {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function grantRole(bytes32 role, address account) external;
}

contract HyperTest is Test {
    IAlgebraFactory private constant KITTEN_SWAP_FACTORY = IAlgebraFactory(0x5f95E92c338e6453111Fc55ee66D4AafccE661A7);
    ISwapRouter private constant KITTEN_SWAP_ROUTER = ISwapRouter(0x4e73E421480a7E0C24fB3c11019254edE194f736);
    IQuoterV2 private constant KITTEN_QUOTER = IQuoterV2(0xc58874216AFe47779ADED27B8AAd77E8Bd6eBEBb);
    INonfungiblePositionManager private constant KITTEN_NFT_MANAGER =
        INonfungiblePositionManager(0x9ea4459c8DefBF561495d95414b9CF1E2242a3E2);

    bytes32 private constant DEFAULT_ADMIN_ROLE =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    address private immutable DEFAULT_ADMIN_ROLE_KITTEN_ALGEBRA_FACTORY;

    address private poolAdmin = makeAddr("POOLS_ADMINISTRATOR_ROLE_ALGEBRA_FACTORY");
    address private feeAddress = makeAddr("FEE_ADDRESS");

    address private plugin;
    IAlgebraPool private pool;
    MockERC20 private token0;
    MockERC20 private token1;

    constructor() {
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

    function setUp() public {
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
        deployAndInitializePool();
        mintLiquidity();
    }

    function deployAndInitializePool() public {
        pool = IAlgebraPool(
            KITTEN_SWAP_FACTORY.createCustomPool(address(this), address(this), address(token0), address(token1), "")
        );
        console.log("pool deployed at: ", address(pool), pool.plugin());
        pool.initialize(7922816251426433759354395033600000);
    }

    function mintLiquidity() public {
        //         tickLower: parseInt(process.env.TICK_LOWER || "-887220"),
        // tickUpper: parseInt(process.env.TICK_UPPER || "887220"),

        token0.mint(address(this), 1e22);
        token1.mint(address(this), 1e22);
        token0.approve(address(KITTEN_NFT_MANAGER), type(uint256).max);
        token1.approve(address(KITTEN_NFT_MANAGER), type(uint256).max);
        
        //     address token0;
        // address token1;
        // address deployer;
        // int24 tickLower;
        // int24 tickUpper;
        // uint256 amount0Desired;
        // uint256 amount1Desired;
        // uint256 amount0Min;
        // uint256 amount1Min;
        // address recipient;
        // uint256 deadline;

        KITTEN_NFT_MANAGER.mint(
            INonfungiblePositionManager.MintParams{
                token0: address(token0),
                token1: address(token1),
                deployer: address(this),
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: 1e18,
                amount1Desired: 1e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 15
            }
        );
    }

    function testSwap() public {
        token0.mint(address(this), 1e22);
        token0.approve(address(KITTEN_SWAP_ROUTER), type(uint256).max);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            deployer: address(this),
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: 1e18,
            amountOutMinimum: 0,
            limitSqrtPrice: 0
        });

        uint256 amountOut = KITTEN_SWAP_ROUTER.exactInputSingle(params);
        console.log("swapped 1e18 T0 for ", amountOut, " T1");
    }

    function beforeCreatePoolHook(
        address pool,
        address creator,
        address deployer,
        address token0,
        address token1,
        bytes calldata data
    ) external returns (address) {
        HyperPlugin _plugin =
            new HyperPlugin(IAlgebraPool(pool), IHyperFactory(msg.sender), ISwapRouter(KITTEN_SWAP_ROUTER), feeAddress);
        console.log("plugin deployed at: ", address(_plugin));
        return address(_plugin);
    }

    function afterCreatePoolHook(address plugin, address pool, address deployer) external view {}
}
