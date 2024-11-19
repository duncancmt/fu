// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";
import {uint512, tmp, alloc} from "src/lib/512Math.sol";

import {Test} from "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";

contract ReflectMathTest is Test {
    uint256 internal constant feeRate = ReflectMath.feeBasis / 100;

    function testTransfer(
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares,
        uint256 amount
    ) external view {
        totalSupply = bound(totalSupply, 10 ** Settings.DECIMALS, Settings.INITIAL_SUPPLY);
        totalShares = bound(totalShares, totalSupply, Settings.INITIAL_SHARES);
        {
            uint256 minShares = totalShares / totalSupply;
            minShares = minShares == 0 ? 1 : minShares;
            fromShares = bound(fromShares, minShares, totalShares);
        }
        toShares = bound(toShares, 0, totalShares - fromShares);

        uint256 fromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        assertGt(fromBalance, 0);
        amount = bound(amount, 1, fromBalance);
        vm.assume(amount < totalSupply / 2); // TODO: remove
        uint256 toBalance = tmp().omul(toShares, totalSupply).div(totalShares);

        (uint256 transferShares, uint256 burnShares) = ReflectMath.getTransferShares(amount, feeRate, totalSupply, totalShares, fromShares, toShares);
        uint256 newFromShares = fromShares - transferShares;
        uint256 newToShares = toShares + transferShares - burnShares;
        uint256 newTotalShares = totalShares - burnShares;

        uint256 newFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        uint256 newToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
    }
}
