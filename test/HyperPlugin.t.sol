// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {KittenTestBase} from "test/helpers/KittenTestBase.t.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {IHyperStrategy} from "src/interfaces/IHyperStrategy.sol";
import {HyperPlugin} from "src/HyperPlugin.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {HyperStrategy} from "src/HyperStrategy.sol";

contract HyperPluginTest is KittenTestBase {
    HyperPlugin internal plugin;

    function setUp() public {
        setUpFixture();
        plugin = HyperPlugin(payable(pool.plugin()));
    }

    function test_SetBurnBps_Succeeds() public {
        // default is 800_000; change to 500_000
        plugin.setBurnBps(500_000);
        assertEq(plugin.burnBps(), 500_000, "burn bps updated");
    }

    function test_SetBurnBps_RevertWhen_AboveMax() public {
        vm.expectRevert(HyperPlugin.InvalidBurnBps.selector);
        plugin.setBurnBps(1_000_001);
    }

    function test_handlePluginFee_BurnsStrategyTokenOnDirectBurnPath() public {
        // Arrange: ensure direct burn path is taken for one side
        bool strategyIsToken0 = plugin.strategyIsToken0();

        // Fund plugin with strategy tokens by transferring from owner through whitelisted path
        // Allow transfer by whitelisting this test and plugin addresses
        HyperStrategy hs = HyperStrategy(hyperStrategy);
        hs.setTransferAddressWhitelist(address(this), true);
        hs.setTransferAddressWhitelist(address(plugin), true);
        // Transfer from owner (this) to plugin
        hs.transfer(address(plugin), 1_000 ether);

        // Set burn to 50%
        plugin.setBurnBps(500_000);

        // Determine which side to charge to trigger direct burn of strategy token
        uint256 fee0 = 0;
        uint256 fee1 = 0;
        uint256 charge = 200 ether; // plugin "fee" value used only to compute burn amount
        if (strategyIsToken0) {
            fee0 = charge; // strategy token is token0 -> direct burn happens on pluginFee0 path
        } else {
            fee1 = charge; // strategy token is token1 -> direct burn happens on pluginFee1 path
        }

        // Expect burn event
        vm.expectEmit(true, false, false, true);
        emit HyperPlugin.Burn(address(hyperStrategy), charge / 2);

        // Act: only pool may call
        vm.prank(address(pool));
        plugin.handlePluginFee(fee0, fee1);

        // Assert: half was burned (sent to DEAD), half remained for withdrawal
        uint256 balanceAfter = MockERC20(address(hyperStrategy)).balanceOf(address(plugin));
        assertEq(balanceAfter, 1_000 ether - (charge / 2), "remaining strategy balance in plugin");
    }
}


