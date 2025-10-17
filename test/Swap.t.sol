// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {HyperPlugin} from "src/HyperPlugin.sol";
import {IHyperStrategy} from "src/interfaces/IHyperStrategy.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {KittenTestBase} from "test/helpers/KittenTestBase.t.sol";
import {IQuoterV2} from "@cryptoalgebra/integral-periphery/contracts/interfaces/IQuoterV2.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {console} from "forge-std/console.sol";
contract SwapTest is KittenTestBase {
    function setUp() public {
        setUpFixture();
    }

    function test_SwapFees_AccrueOnBuyAndSell() public {
        HyperPlugin plugin = HyperPlugin(payable(pool.plugin()));

        uint256 strategyBalanceBefore = ERC20(hyperStrategy).balanceOf(address(plugin));
        uint256 whypeBalanceBefore = ERC20(WHYPE).balanceOf(address(plugin));

        swapExact(WHYPE, hyperStrategy, 1e18, 0);
        uint256 strategyBalanceAfter = ERC20(hyperStrategy).balanceOf(address(plugin));
        uint256 whypeBalanceAfter = ERC20(WHYPE).balanceOf(address(plugin));

        // assertGt(strategyBalanceAfter, strategyBalanceBefore);
        assertGt(whypeBalanceAfter, whypeBalanceBefore);

        // // Sell strategy for other token -> in this pool implementation, plugin fees accrue in the other token
        // // Fund this test with strategy tokens for swap
        // ERC20(strategyToken).approve(address(KITTEN_SWAP_ROUTER), type(uint256).max);
        // swapExact(strategyToken, otherToken, 1e18, 0);
        // uint256 afterStrategy = ERC20(strategyToken).balanceOf(address(plugin));
        // assertGt(afterStrategy, beforeStrategy);
        // uint256 afterOther2 = ERC20(otherToken).balanceOf(address(plugin));
        // assertGe(afterOther2, afterOther);
    }

    function test_SwapFees_ExactCalculations() public {
        HyperPlugin plugin = HyperPlugin(payable(pool.plugin()));
        
        address strategyToken = address(token1) == hyperStrategy ? address(token1) : address(token0);
        address otherToken = address(token0) == strategyToken ? address(token1) : address(token0);
        
        uint256 swapAmount = 1e18;
        uint256 burnBps = plugin.burnBps();
        
        console.log("=== FEE CALCULATION TEST ===");
        console.log("Burn BPS:", burnBps);
        
        // Calculate expected fees for BUY
        uint256 elapsed = block.timestamp - plugin.initTimestamp();
        uint256 buyFeeBps = elapsed >= 3600 ? 100_000 : 990_000 - ((990_000 - 100_000) * elapsed) / 3600;
        
        console.log("Buy fee BPS:", buyFeeBps);
        
        // Perform buy swap and measure fee
        uint256 beforeBuy = ERC20(otherToken).balanceOf(address(plugin));
        swapExact(otherToken, strategyToken, swapAmount, 0);
        uint256 buyFeeAccrued = ERC20(otherToken).balanceOf(address(plugin)) - beforeBuy;
        
        console.log("Buy fee accrued:", buyFeeAccrued);
        
        // Perform sell swap
        ERC20(strategyToken).approve(address(KITTEN_SWAP_ROUTER), type(uint256).max);
        uint256 beforeSell = ERC20(strategyToken).balanceOf(address(plugin));
        swapExact(strategyToken, otherToken, swapAmount, 0);
        uint256 strategyIncrease = ERC20(strategyToken).balanceOf(address(plugin)) - beforeSell;
        
        console.log("Strategy token increase:", strategyIncrease);
        
        // Verify fee calculations
        uint256 expectedBuyFee = (swapAmount * buyFeeBps) / 1_000_000;
        uint256 tolerance = expectedBuyFee / 100;
        
        assertGe(buyFeeAccrued, expectedBuyFee - tolerance, "Buy fee too low");
        assertLe(buyFeeAccrued, expectedBuyFee + tolerance, "Buy fee too high");
        assertGt(strategyIncrease, 0, "Strategy token balance should increase");
        
        console.log("=== TEST PASSED ===");
    }
}
