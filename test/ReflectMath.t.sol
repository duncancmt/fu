// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UnsafeMath} from "src/lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "src/lib/512Math.sol";
import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";

import {Test} from "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";

contract ReflectMathTest is Test {
    using UnsafeMath for uint256;

    function _oneTokenInShares(uint256 totalSupply, uint256 totalShares) internal pure returns (uint256) {
        uint256 oneTokenInShares;
        uint512 tmp1 = alloc().omul(10 ** Settings.DECIMALS, totalShares);
        oneTokenInShares = tmp1.div(totalSupply);
        if (tmp().omul(oneTokenInShares, totalSupply) < tmp1) {
            oneTokenInShares++;
        }
        assertTrue(tmp().omul(oneTokenInShares, totalSupply) >= tmp1);
        return oneTokenInShares;
    }

    function _boundCommon(uint256 totalSupply, uint256 totalShares, uint256 fromShares, uint256 amount)
        internal
        pure
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        uint256 initialSharesRatio = Settings.INITIAL_SHARES / Settings.INITIAL_SUPPLY;
        totalSupply = bound(totalSupply, 10 ** Settings.DECIMALS + 1, Settings.INITIAL_SUPPLY);
        totalShares = bound(totalShares, totalSupply * (initialSharesRatio >> 20), Settings.INITIAL_SHARES); // TODO: reduce multiplier
        uint256 oneTokenInShares = _oneTokenInShares(totalSupply, totalShares);
        uint256 oneWeiInShares = totalShares / totalSupply;
        if (oneWeiInShares * totalSupply < totalShares) {
            oneWeiInShares++;
        }
        vm.assume(oneWeiInShares < totalShares - oneTokenInShares); // only possible in extreme conditions due to rounding error
        fromShares = bound(fromShares, oneWeiInShares, totalShares - oneTokenInShares);
        uint256 fromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        assertGt(fromBalance, 0);
        amount = bound(amount, 1, fromBalance);

        return (totalSupply, totalShares, fromShares, fromBalance, amount);
    }

    function testTransfer(
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares,
        uint256 amount,
        uint16 feeRate
    ) external view {
        uint256 fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount);

        feeRate = uint16(bound(feeRate, Settings.MIN_FEE, Settings.MAX_FEE));

        toShares = bound(toShares, 0, totalShares - _oneTokenInShares(totalSupply, totalShares) - fromShares);
        vm.assume(fromShares + toShares < totalShares / 2);
        uint256 toBalance = tmp().omul(toShares, totalSupply).div(totalShares);

        console.log("===");
        console.log("totalSupply", totalSupply);
        console.log("feeRate    ", feeRate);
        console.log("amount     ", amount);
        console.log("===");
        console.log("fromBalance", fromBalance);
        console.log("toBalance  ", toBalance);
        console.log("===");
        (uint256 newFromShares, uint256 newToShares, uint256 newTotalShares) =
            ReflectMath.getTransferShares(amount, feeRate, totalSupply, totalShares, fromShares, toShares);
        assertLe(newFromShares, fromShares, "from shares increased");
        assertGe(newToShares, toShares, "to shares decreased");
        assertLe(newTotalShares, totalShares, "total shares increased");

        uint256 newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        uint256 newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        uint256 expectedNewFromBalance = fromBalance - amount;
        uint256 expectedNewToBalance = toBalance + amount * (ReflectMath.feeBasis - feeRate) / ReflectMath.feeBasis;

        assertEq(newFromBalance, expectedNewFromBalance, "newFromBalance");
        // TODO: tighten these bounds to exact equality
        assertLe(
            newToBalance,
            toBalance + (amount * (ReflectMath.feeBasis - feeRate)).unsafeDivUp(ReflectMath.feeBasis),
            "newToBalance upper"
        );
        assertGe(newToBalance, expectedNewToBalance, "newToBalance lower");
    }

    function testDeliver(uint256 totalSupply, uint256 totalShares, uint256 fromShares, uint256 amount) external view {
        uint256 fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount);
        vm.assume(fromShares < totalShares / 2);

        (uint256 newFromShares, uint256 newTotalShares) =
            ReflectMath.getDeliverShares(amount, totalSupply, totalShares, fromShares);
        assertLe(newFromShares, fromShares);
        assertLe(newTotalShares, totalShares);

        uint256 newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        uint256 expectedNewFromBalance = fromBalance - amount;

        assertEq(newFromBalance, expectedNewFromBalance, "new balance, expected new balance");
    }
}
