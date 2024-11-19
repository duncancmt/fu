// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {uint512, tmp, alloc} from "../lib/512Math.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    uint256 internal constant feeBasis = 10_000;

    function getTransferShares(
        uint256 amount,
        uint256 feeRate,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares
    ) internal view returns (uint256 transferShares, uint256 burnShares) {
        uint256 uninvolvedShares = totalShares - fromShares - toShares;
        uint512 totalSharesSquared = alloc().omul(totalShares, totalShares);
        uint512 n = alloc().omul(totalSharesSquared, amount * feeRate);
        uint512 t1 = alloc().omul(uninvolvedShares, feeRate * totalSupply);
        uint512 t2 = alloc().omul(feeBasis * totalSupply, uninvolvedShares);
        uint512 d = alloc().oadd(t1, t2);

        burnShares = n.div(d); // TODO: round up?

        uint512 ab = alloc().omul(fromShares, totalSupply);
        uint512 cd = alloc().omul(amount, totalShares);
        uint512 diff = alloc().osub(ab, cd);
        uint512 term1 = alloc().omul(diff, burnShares);
        uint512 amount_totalSharesSquared = alloc().omul(totalSharesSquared, amount);
        n.oadd(term1, amount_totalSharesSquared);
        d.omul(totalSupply, totalShares);

        transferShares = n.div(d); // TODO: round up?

        return (transferShares, burnShares);
    }

    function getDeliverShares(
        uint256 amount,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares
    ) internal view returns (uint256) {
        revert("unimplemented");
    }
}
