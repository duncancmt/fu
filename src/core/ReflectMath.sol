// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {uint512, tmp, alloc} from "../lib/512Math.sol";

import {console} from "@forge-std/console.sol";

library ReflectMath {
    uint256 internal constant feeBasis = 10_000;

    function debit(
        uint256 amount,
        uint256 feeRate,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares
    ) internal view returns (uint256, uint256) {
        console.log("debit");
        console.log("amount", amount);
        console.log("feeRate", feeRate);
        console.log("totalSupply", totalSupply);
        console.log("totalShares", totalShares);
        console.log("fromShares", fromShares);
        console.log("toShares", toShares);

        uint512 n = alloc().omul(totalSupply * feeBasis, fromShares);
        console.log("1");
        n.iadd(tmp().omul(amount * feeBasis, toShares));
        console.log("2");
        assert(n > tmp().omul(amount * feeBasis, totalShares));
        n.isub(tmp().omul(amount * feeBasis, totalShares));
        console.log("3");
        assert(n > tmp().omul(amount, fromShares * (feeBasis - feeRate)));
        n.isub(tmp().omul(amount, fromShares * (feeBasis - feeRate)));
        console.log("4");
        uint256 d = totalSupply * feeBasis;
        console.log("4a");
        console.log("d", d);
        d -= amount * ((feeBasis << 1) - feeRate);
        console.log("5");

        uint256 debitShares = n.div(d);
        console.log("6");
        if (tmp().omul(debitShares, d) < n) {
            debitShares++;
        }
        console.log("7");

        console.log("fromShares", fromShares);
        console.log("debitShares", debitShares);

        return (fromShares - debitShares, debitShares);
    }

    function credit(
        uint256 amount,
        uint256 feeRate,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 toShares,
        uint256 debitShares
    ) internal view returns (uint256, uint256) {
        uint512 n = alloc().omul(totalSupply * feeBasis, toShares);
        console.log("8");
        n.iadd(tmp().omul(totalSupply * feeBasis, debitShares));
        console.log("9");
        assert(n > tmp().omul(amount, totalShares * (feeBasis - feeRate)));
        n.isub(tmp().omul(amount, totalShares * (feeBasis - feeRate)));
        console.log("10");
        uint256 d = totalSupply * feeBasis - amount * (feeBasis - feeRate);

        console.log("11");
        uint256 burnShares = n.div(d);
        // TODO: should this round up?

        console.log("toShares", toShares);
        console.log("debitShares", debitShares);
        console.log("burnShares", burnShares);
        return (toShares + debitShares - burnShares, totalShares - burnShares);
    }
}
