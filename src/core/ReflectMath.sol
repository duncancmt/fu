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
    ) internal view returns (uint256 transferShares, uint256 burnShares) {
        console.log("1");
        uint256 uninvolvedShares = totalShares - fromShares - toShares;
        console.log("2");
        uint512 totalSharesSquared = alloc().omul(totalShares, totalShares);
        console.log("3");
        uint512 n = alloc().omul(totalSharesSquared, amount * feeRate);
        console.log("4");
        uint512 t1 = alloc().omul(amount * feeRate, totalShares);
        console.log("5");
        uint512 t2 = alloc().omul(feeBasis * totalSupply, uninvolvedShares);
        console.log("6");
        uint512 d = alloc().oadd(t1, t2);
        console.log("7");

        uint256 tmp1;
        (tmp1, burnShares) = tmp().odiv(n, d).into();
        console.log("should be zero", tmp1);
        /*
        if (tmp().omul(d, burnShares) < n) {
            burnShares = burnShares.unsafeInc();
        }
        */

        console.log("8");
        uint512 ab = alloc().omul(fromShares, totalSupply);
        console.log("9");
        uint512 cd = alloc().omul(amount, totalShares);
        console.log("10");
        uint512 diff = alloc().osub(ab, cd);
        console.log("11");
        uint512 term1 = alloc().omul(diff, burnShares);
        console.log("12");
        uint512 amount_totalSharesSquared = alloc().omul(totalSharesSquared, amount);
        console.log("13");
        n.oadd(term1, amount_totalSharesSquared);
        console.log("14");
        d.omul(totalSupply, totalShares);
        console.log("15");

        (tmp1, transferShares) = tmp().odiv(n, d).into();
        console.log("should be zero", tmp1);
        /*
        if (tmp().omul(d, transferShares) < n) {
            transferShares = transferShares.unsafeInc();
        }
        */
    }

    function getDeliverShares(uint256 amount, uint256 totalSupply, uint256 totalShares, uint256 fromShares)
        internal
        view
        returns (uint256)
    {
        revert("unimplemented");
    }
}
