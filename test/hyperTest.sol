// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {console} from "forge-std/console.sol";
import {IAlgebraFactory} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraFactory.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
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
    bytes32 private constant DEFAULT_ADMIN_ROLE =
        bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    address private immutable DEFAULT_ADMIN_ROLE_KITTEN_ALGEBRA_FACTORY;

    address private poolAdmin = makeAddr("POOLS_ADMINISTRATOR_ROLE_ALGEBRA_FACTORY");
    address private customPoolDeployer = makeAddr("CUSTOM_POOL_DEPLOYER_ALGEBRA_FACTORY");
    address private feeAddress = makeAddr("FEE_ADDRESS");

    address private plugin;
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
            IAlgebraFactory(KITTEN_SWAP_FACTORY).CUSTOM_POOL_DEPLOYER(), customPoolDeployer
        );
        vm.stopPrank();
    }

    function beforeCreatePoolHook(
        address pool,
        address creator,
        address deployer,
        address token0,
        address token1,
        bytes calldata data
    ) external returns (address) {
        HyperPlugin _plugin = new HyperPlugin(
            IAlgebraPool(pool),
            IHyperFactory(msg.sender),
            ISwapRouter(KITTEN_SWAP_ROUTER),
            feeAddress
        );
        console.log("plugin deployed at: ", address(_plugin));
        return address(_plugin);
    }

    function afterCreatePoolHook(
        address pool,
        address creator,
        address deployer,
        address token0,
        address token1,
        bytes calldata data
    ) external {}

    function setUp() public {
        token0 = new MockERC20("Token0", "T0");
        token1 = new MockERC20("Token1", "T1");
    }

    function testSetup() public {
        vm.prank(customPoolDeployer);
        address pool = KITTEN_SWAP_FACTORY.createCustomPool(
            address(this),
            address(this),
            address(token0),
            address(token1),
            ""
        );
        console.log("pool deployed at: ", pool);
        // vm.prank(poolAdmin);
        // IAlgebraPool(pool).setPlugin(address(plugin));
    }
}
