// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UnsafeMath} from "src/lib/UnsafeMath.sol";
import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";
import {uint512, tmp, alloc} from "src/lib/512Math.sol";

import {Test} from "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";

contract ReflectMathTest is Test {
    using UnsafeMath for uint256;

    uint256 internal constant feeRate = ReflectMath.feeBasis / 100;

    function testTransfer(
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares,
        uint256 amount
    ) external view {
        uint256 initialSharesRatio = Settings.INITIAL_SHARES / Settings.INITIAL_SUPPLY;
        totalSupply = bound(totalSupply, 10 ** Settings.DECIMALS + 1, Settings.INITIAL_SUPPLY);
        totalShares = bound(totalShares, totalSupply * (initialSharesRatio >> 20), Settings.INITIAL_SHARES); // TODO: reduce multiplier

        console.log("totalSupply", totalSupply);
        console.log("totalShares", totalShares);

        uint256 oneTokenInShares;
        {
            uint512 tmp1 = alloc().omul(10 ** Settings.DECIMALS, totalShares);
            oneTokenInShares = tmp1.div(totalSupply);
            if (tmp().omul(oneTokenInShares, totalSupply) < tmp1) {
                oneTokenInShares++;
            }
            assertTrue(tmp().omul(oneTokenInShares, totalSupply) >= tmp1);
        }
        uint256 oneWeiInShares = totalShares / totalSupply;
        if (oneWeiInShares * totalSupply < totalShares) {
            oneWeiInShares++;
        }
        console.log("one token  ", oneTokenInShares);
        console.log("one wei    ", oneWeiInShares);

        vm.assume(oneWeiInShares < totalShares - oneTokenInShares); // only possible in extreme conditions due to rounding error
        fromShares = bound(fromShares, oneWeiInShares, totalShares - oneTokenInShares);
        toShares = bound(toShares, 0, totalShares - oneTokenInShares - fromShares);

        console.log("fromShares ", fromShares);
        console.log("toShares   ", toShares);

        vm.assume((fromShares + toShares) * 2 <= totalShares); // TODO: reduce multiplier

        uint256 fromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        assertGt(fromBalance, 0);
        amount = bound(amount, 1, fromBalance);
        uint256 toBalance = tmp().omul(toShares, totalSupply).div(totalShares);

        console.log("amount     ", amount);
        console.log("===");
        console.log("fromBalance", fromBalance);
        console.log("toBalance  ", toBalance);
        console.log("===");
        (uint256 transferShares, uint256 burnShares) =
            ReflectMath.getTransferShares(amount, feeRate, totalSupply, totalShares, fromShares, toShares);
        console.log("transferShares", transferShares);
        console.log("burnShares", burnShares);
        assertLe(transferShares, fromShares, "transferShares");
        assertLt(burnShares, transferShares, "burnShares");

        uint256 newFromShares = fromShares - transferShares;
        uint256 newToShares = toShares + transferShares - burnShares;
        uint256 newTotalShares = totalShares - burnShares;

        uint256 expectedNewFromBalance = fromBalance - amount;
        uint256 expectedNewToBalance = toBalance + amount * (ReflectMath.feeBasis - feeRate) / ReflectMath.feeBasis;

        uint256 newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        if (newToBalance < expectedNewToBalance) {
            console.log("newToBalance too low");
            uint256 incr = tmp().omul(expectedNewToBalance - newToBalance, newTotalShares).div(totalSupply);
            newToShares += incr;
            newTotalShares += incr;
            newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        }

        uint256 newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        if (newFromBalance > expectedNewFromBalance) {
            console.log("newFromBalance too high");
            uint256 decr = tmp().omul(newFromBalance - expectedNewFromBalance, newTotalShares).div(totalSupply);
            newFromShares -= decr;
            newTotalShares -= decr;

            newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
            newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        } else if (newFromBalance < expectedNewFromBalance) {
            console.log("newFromBalance too low");
            uint256 incr = tmp().omul(expectedNewFromBalance - newFromBalance, newTotalShares).div(totalSupply);
            newFromShares += incr;
            newTotalShares += incr;

            newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
            newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        }

        assertLe(newTotalShares, totalShares);

        assertEq(newFromBalance, fromBalance - amount, "newFromBalance");
        // TODO: tighten these bounds to exact equality
        assertLe(
            newToBalance, toBalance + (amount * (ReflectMath.feeBasis - feeRate)).unsafeDivUp(ReflectMath.feeBasis), "newToBalance upper"
        );
        assertGe(newToBalance, expectedNewToBalance, "newToBalance lower");
    }
}
