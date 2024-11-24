// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares} from "./types/Shares.sol";
import {Balance} from "./types/Balance.sol";
import {scale} from "./types/SharesXBasisPoints.sol";
import {scale, castUp} from "./types/BalanceXBasisPoints.sol";
import {BalanceXShares, tmp, alloc, cast} from "./types/BalanceXShares.sol";
import {BalanceXShares2, tmp as tmp2, alloc as alloc2, cast} from "./types/BalanceXShares2.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    using UnsafeMath for uint256;

    function getTransferShares(
        Balance amount,
        BasisPoints feeRate,
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal view returns (Shares newFromShares, Shares newToShares, Shares newTotalShares) {
        // TODO: introduce a SharesXBasisPoints type
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        BalanceXShares t1 = alloc().omul(fromShares, totalSupply);
        BalanceXShares t2 = alloc().omul(amount, totalShares);
        BalanceXShares t3 = alloc().osub(t1, t2);
        BalanceXShares2 n1 = alloc2().omul(t3, scale(uninvolvedShares, BASIS));
        BalanceXShares t4 = alloc().omul(totalSupply, scale(uninvolvedShares, BASIS));
        BalanceXShares t5 = alloc().omul(amount, scale(totalShares, feeRate));
        BalanceXShares d = alloc().oadd(t4, t5);
        BalanceXShares t6 = alloc().omul(amount, scale(totalShares, BASIS - feeRate));
        BalanceXShares t7 = alloc().omul(scale(toShares, BASIS), totalSupply);
        BalanceXShares t8 = alloc().oadd(t6, t7);
        BalanceXShares2 n2 = alloc2().omul(t8, uninvolvedShares);

        {
            (uint256 x, uint256 y) = cast(n1).divMulti(cast(n2), cast(d));
            (newFromShares, newToShares) = (Shares.wrap(x), Shares.wrap(y));
        }
        // console.log("    fromShares", fromShares);
        // console.log(" newFromShares", newFromShares);
        // console.log("      toShares", toShares);
        // console.log("   newToShares", newToShares);
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);
        // console.log("   totalShares", totalShares);
        // console.log("newTotalShares", newTotalShares);

        // Fixup rounding error
        console.log("===");
        // TODO use divMulti to compute beforeToBalance and beforeFromBalance (can't use it for after because newTotalShares might change)
        Balance beforeToBalance = tmp().omul(toShares, totalSupply).div(totalShares);
        Balance afterToBalance = tmp().omul(newToShares, totalSupply).div(newTotalShares);
        Balance expectedAfterToBalanceLo = beforeToBalance + amount - castUp(scale(amount, feeRate));
        Balance expectedAfterToBalanceHi = beforeToBalance + castUp(scale(amount, BASIS - feeRate));

        {
            bool condition = afterToBalance < expectedAfterToBalanceLo;
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
        {
            bool condition = afterToBalance > expectedAfterToBalanceHi;
            newToShares = newToShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }

        // console.log("===");
        Balance beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        Balance afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        Balance expectedAfterFromBalance = beforeFromBalance - amount;
        // console.log("  actual fromBalance", afterFromBalance);
        // console.log("expected fromBalance", expectedAfterFromBalance);
        {
            bool condition = afterFromBalance > expectedAfterFromBalance;
            newFromShares = newFromShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }
        {
            bool condition = afterFromBalance < expectedAfterFromBalance;
            newFromShares = newFromShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
    }

    function getDeliverShares(Balance amount, Balance totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares)
    {
        BalanceXShares t1 = alloc().omul(fromShares, totalSupply);
        BalanceXShares t2 = alloc().omul(amount, totalShares);
        BalanceXShares t3 = alloc().osub(t1, t2);
        BalanceXShares2 n = alloc2().omul(t3, totalShares - fromShares);
        BalanceXShares t4 = alloc().omul(totalSupply, totalShares - fromShares);
        BalanceXShares d = alloc().oadd(t4, t2);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);

        // Fixup rounding error
        Balance beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        Balance afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        Balance expectedAfterFromBalance = beforeFromBalance - amount;
        bool condition = afterFromBalance < expectedAfterFromBalance;
        newFromShares = newFromShares.inc(condition);
        newTotalShares = newTotalShares.inc(condition);
    }

    function getBurnShares(Balance amount, Balance totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        returns (Shares newFromShares, Shares newTotalShares, Balance newTotalSupply)
    {
        revert("unimplemented");
    }
}
