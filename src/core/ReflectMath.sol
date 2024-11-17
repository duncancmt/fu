// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {uint512, tmp, alloc} from "../lib/512Math.sol";

library ReflectMath {
    uint256 internal constant feeRate = 100;
    uint256 internal constant feeBasis = 10_000;
    
    function debit(
        uint256 amount,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 fromShares,
        uint256 toShares
    ) internal pure returns (uint256, uint256) {
        uint512 n = alloc().omul(totalSupply * feeBasis, fromShares);
        n.iadd(tmp().omul(amount * feeBasis, toShares));
        n.isub(tmp().omul(amount * feeBasis, totalShares));
        n.isub(tmp().omul(amount, fromShares * (feeBasis - feeRate)));
        uint256 d = totalSupply * feeBasis - amount * ((feeBasis << 1) - feeRate);

        uint256 debitShares = n.div(d);
        if (tmp().omul(debitShares, d) < n) {
            debitShares++;
        }

        return (fromShares - debitShares, debitShares);
    }

    function credit(
        uint256 amount,
        uint256 totalSupply,
        uint256 totalShares,
        uint256 toShares,
        uint256 debitShares
    ) internal pure returns (uint256, uint256) {
        uint512 n = alloc().omul(totalSupply * feeBasis, toShares);
        n.iadd(tmp().omul(totalSupply * feeBasis, debitShares));
        n.isub(tmp().omul(amount, totalShares * (feeBasis - feeRate)));
        uint256 d = totalSupply * feeBasis - amount * (feeBasis - feeRate);

        uint256 burnShares = n.div(d);
        // TODO: should this round up?
        return (toShares + debitShares - burnShares, totalShares - burnShares);
    }
}
