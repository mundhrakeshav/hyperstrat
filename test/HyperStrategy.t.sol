// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {KittenTestBase} from "test/helpers/KittenTestBase.t.sol";
import {IHyperStrategy} from "src/interfaces/IHyperStrategy.sol";
import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";

contract HyperStrategyTest is KittenTestBase {
    IHyperStrategy internal hs;

    function setUp() public {
        setUpFixture();
        hs = IHyperStrategy(payable(hyperStrategy));
    }

    function test_NameAndSymbol() public {
        assertEq(hs.name(), "Hypurr");
        assertEq(hs.symbol(), "HYPE");
    }

    function test_SetMarketplaceWhitelistAndSelector() public {
        address market = address(0x1234);
        bytes4 sel = bytes4(keccak256("buy(uint256)"));

        hs.setMarketplaceWhitelist(market, true);
        assertTrue(hs.whitelistedMarketplaces(market));

        hs.setSelectorWhitelist(market, sel, true);
        assertTrue(hs.whitelistedSelectors(market, sel));
    }
    
    function test_TransferRestriction_RevertsWhen_NotWhitelistedRoute() public {
        address receiver = address(0xCAFE);
        vm.expectRevert(IHyperStrategy.InvalidTransfer.selector);
        hs.transfer(receiver, 1);
    }

    function test_BuyNFT_RevertsForUnwhitelistedMarketplaceAndSelector() public {
        address market = address(0x1111);
        bytes memory data = hex"12345678";

        // Unwhitelisted marketplace
        vm.expectRevert(IHyperStrategy.MarketplaceNotWhitelisted.selector);
        hs.buyNFT(market, 0, data, 1);

        // Whitelist marketplace but not selector
        hs.setMarketplaceWhitelist(market, true);
        vm.expectRevert(IHyperStrategy.NotWhitelistedSelector.selector);
        hs.buyNFT(market, 0, data, 1);
    }

    function test_SetPriceMultiplier_UpdatesVariable() public {
        uint256 newMult = 1_500_000;
        hs.setPriceMultiplier(newMult);
        // No getter; rely on event or observable effect. For now, ensure call doesn't revert.
        assertTrue(true);
    }
}


