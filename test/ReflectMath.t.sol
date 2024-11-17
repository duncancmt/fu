// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ReflectMath} from "src/core/ReflectMath.sol";
import {uint512, tmp, alloc} from "src/lib/512Math.sol";

import {Test} from "@forge-std/Test.sol";

contract ReflectMathTest is Test {
    uint256 internal constant feeRate = ReflectMath.feeBasis / 100;

    function testTransfer(
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares,
        uint256 amount
    ) external view {
        totalSupply = bound(totalSupply, uint256(1e36), uint256(type(uint112).max) * type(uint40).max);
        totalShares = bound(totalShares, uint256(1e36) * type(uint64).max, type(uint256).max / type(uint40).max / ReflectMath.feeBasis);
        {
            uint256 minShares = totalShares / totalSupply;
            minShares = minShares == 0 ? 1 : minShares;
            fromShares = bound(fromShares, minShares, totalShares);
        }
        toShares = bound(toShares, 0, totalShares - fromShares);

        uint256 fromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        assertGt(fromBalance, 0);
        amount = bound(amount, 1, fromBalance);
        uint256 toBalance = tmp().omul(toShares, totalSupply).div(totalShares);

        (uint256 newFromShares, uint256 debitShares) =
            ReflectMath.debit(amount, feeRate, totalSupply, totalShares, fromShares, toShares);
        (uint256 newToShares, uint256 newTotalShares) =
            ReflectMath.credit(amount, feeRate, totalSupply, totalShares, toShares, debitShares);

        uint256 newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        uint256 newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
    }
}
