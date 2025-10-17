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
        plugin.setBurnBps(800_000);
        assertEq(plugin.burnBps(), 800_000, "burn bps updated");
    }

    function test_SetBurnBps_RevertWhen_AboveMax() public {
        vm.expectRevert(HyperPlugin.InvalidBurnBps.selector);
        plugin.setBurnBps(1_000_001);
    }

    // function test_handlePluginFee_BurnsStrategyTokenOnDirectBurnPath() public {
    //     bool strategyIsToken0 = plugin.strategyIsToken0();
    //     HyperStrategy hs = HyperStrategy(hyperStrategy);
    //     hs.setTransferAddressWhitelist(address(this), true);
    //     hs.setTransferAddressWhitelist(address(plugin), true);
    //     hs.transfer(address(plugin), 1_000 ether);

    //     plugin.setBurnBps(800_000);

    //     uint256 fee0 = 0;
    //     uint256 fee1 = 0;
    //     uint256 charge = 200 ether;
    //     if (strategyIsToken0) {
    //         fee0 = charge;
    //     } else {
    //         fee1 = charge;
    //     }

    //     vm.expectEmit(true, false, false, true);
    //     emit HyperPlugin.Burn(address(hyperStrategy), (charge * 800_000) / 1_000_000);
    //     vm.prank(address(pool));
    //     plugin.handlePluginFee(fee0, fee1);

    //     uint256 balanceAfter = MockERC20(address(hyperStrategy)).balanceOf(address(plugin));
    //     uint256 expectedRemainder = 1_000 ether - ((charge * 800_000) / 1_000_000);
    //     assertEq(balanceAfter, expectedRemainder, "remaining strategy balance in plugin");
    // }

    // function test_withdraw_SendsAccruedRemainderToOwner() public {
    //     bool strategyIsToken0 = plugin.strategyIsToken0();
    //     HyperStrategy hs = HyperStrategy(hyperStrategy);
    //     hs.setTransferAddressWhitelist(address(this), true);
    //     hs.setTransferAddressWhitelist(address(plugin), true);
    //     hs.transfer(address(plugin), 1_000 ether);

    //     plugin.setBurnBps(800_000);

    //     uint256 fee0 = 0;
    //     uint256 fee1 = 0;
    //     uint256 charge = 400 ether;
    //     if (strategyIsToken0) {
    //         fee0 = charge;
    //     } else {
    //         fee1 = charge;
    //     }

    //     vm.prank(address(pool));
    //     plugin.handlePluginFee(fee0, fee1);

    //     uint256 expectedRemainder = 1_000 ether - ((charge * 800_000) / 1_000_000);
    //     uint256 before = MockERC20(address(hyperStrategy)).balanceOf(address(this));
    //     plugin.withdraw(address(hyperStrategy), type(uint256).max, address(this));
    //     uint256 afterBal = MockERC20(address(hyperStrategy)).balanceOf(address(this));
    //     assertEq(afterBal - before, expectedRemainder, "owner received remainder");
    // }
}


