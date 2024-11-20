// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UnsafeMath} from "../lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "../lib/512Math.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    using UnsafeMath for uint256;

    uint256 internal constant feeBasis = 10_000;

    function getTransferShares(
        uint256 amount,
        uint256 feeRate,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares
    ) internal view returns (uint256 newFromShares, uint256 newToShares, uint256 newTotalShares) {
        uint256 uninvolvedShares = totalShares - fromShares - toShares;
        uint512 totalSharesSquared = alloc().omul(totalShares, totalShares);
        uint512 n = alloc().omul(totalSharesSquared, amount * feeRate);
        uint512 t1 = alloc().omul(amount * feeRate, totalShares);
        uint512 t2 = alloc().omul(feeBasis * totalSupply, uninvolvedShares);
        uint512 d = alloc().oadd(t1, t2);

        uint256 burnShares = n.div(d);

        uint512 ab = alloc().omul(fromShares, totalSupply);
        uint512 cd = alloc().omul(amount, totalShares);
        uint512 diff = alloc().osub(ab, cd);
        uint512 term1 = alloc().omul(diff, burnShares);
        uint512 amount_totalSharesSquared = alloc().omul(totalSharesSquared, amount);
        n.oadd(term1, amount_totalSharesSquared);
        d.omul(totalSupply, totalShares);

        uint256 transferShares = n.div(d);

        newTotalShares = totalShares - burnShares;
        newFromShares = fromShares - transferShares;
        newToShares = toShares + transferShares - burnShares;

        // Fixup rounding error
        {
            uint256 beforeToBalance = tmp().omul(toShares, totalSupply).div(totalShares);
            uint256 afterToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
            uint256 expectedAfterToBalance = beforeToBalance + amount * (feeBasis - feeRate) / feeBasis;
            if (afterToBalance < expectedAfterToBalance) {
                console.log("toBalance too low");
                uint256 incr = tmp().omul(expectedAfterToBalance - afterToBalance, newTotalShares).div(totalSupply);
                newToShares += incr;
                newTotalShares += incr;
            }
        }
        {
            uint256 beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
            uint256 afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
            uint256 expectedAfterFromBalance = beforeFromBalance - amount;
            if (afterFromBalance > expectedAfterFromBalance) {
                console.log("fromBalance too high");
                uint256 decr = tmp().omul(afterFromBalance - expectedAfterFromBalance, newTotalShares).div(totalSupply);
                newFromShares -= decr;
                newTotalShares -= decr;
            } else if (afterFromBalance < expectedAfterFromBalance) {
                console.log("fromBalance too low");
                uint256 incr = tmp().omul(expectedAfterFromBalance - afterFromBalance, newTotalShares).div(totalSupply);
                newFromShares += incr;
                newTotalShares += incr;
            }
        }
    }

    function getDeliverShares(uint256 amount, uint256 totalSupply, uint256 totalShares, uint256 fromShares)
        internal
        view
        returns (uint256)
    {
        revert("unimplemented");
    }
}
