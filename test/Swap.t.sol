// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ISwapRouter} from "@cryptoalgebra/integral-periphery/contracts/interfaces/ISwapRouter.sol";
import {HyperPlugin} from "src/HyperPlugin.sol";
import {IHyperFactory} from "src/HyperInterfaces.sol";
import {IHyperStrategy} from "src/HyperInterfaces.sol";
import {IAlgebraPool} from "@cryptoalgebra/integral-core/contracts/interfaces/IAlgebraPool.sol";
import {KittenTestBase} from "test/helpers/KittenTestBase.t.sol";
import {IQuoterV2} from "@cryptoalgebra/integral-periphery/contracts/interfaces/IQuoterV2.sol";
import {console} from "forge-std/console.sol";

contract SwapTest is KittenTestBase {
    bool private _routerRestrict;

    function setUp() public {
        setUpFixture();
    }

    function testSwap() public {
        address tokenIn = hyperStrategy == address(token0) ? address(token1) : address(token0);
        address tokenOut = hyperStrategy == address(token0) ? address(token0) : address(token1);
        (
            uint256 amountQuotedOut,
            uint256 amountQuotedIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate,
            uint16 fee
        ) = KITTEN_QUOTER.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                deployer: address(this),
                amountIn: 1e18,
                limitSqrtPrice: 0
            })
        );

        console.log("amountQuotedOut:           ", amountQuotedOut);
        console.log("amountQuotedIn:            ", amountQuotedIn);
        console.log("sqrtPriceX96After:         ", sqrtPriceX96After);
        console.log("initializedTicksCrossed:   ", initializedTicksCrossed);
        console.log("gasEstimate:               ", gasEstimate);
        console.log("fee:                       ", fee);

        uint256 amountOut = swapExact(tokenIn, tokenOut, 1e18, 0);
        console.log("swapped 1e18 ", tokenIn);
        console.log("for ", amountOut, tokenOut);

        uint256 balanceToken0 = token0.balanceOf(pool.plugin());
        uint256 balanceToken1 = token1.balanceOf(pool.plugin());
        console.log("balanceToken0: ", balanceToken0);
        console.log("balanceToken1: ", balanceToken1);
    }

    function beforeCreatePoolHook(address pool_, address, address, address, address, bytes calldata)
        external
        override
        returns (address)
    {
        HyperPlugin _plugin = new HyperPlugin(
            IAlgebraPool(pool_),
            IHyperFactory(address(this)),
            ISwapRouter(KITTEN_SWAP_ROUTER),
            IHyperStrategy(hyperStrategy),
            feeAddress
        );
        console.log("plugin deployed at: ", address(_plugin));
        return address(_plugin);
    }

    // Minimal factory surface used by contracts under test
    function routerRestrict() external view returns (bool) {
        return _routerRestrict;
    }
}
