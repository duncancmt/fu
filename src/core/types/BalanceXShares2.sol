// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {Balance} from "./Balance.sol";
import {BalanceXShares, cast} from "./BalanceXShares.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../../lib/512Math.sol";

type BalanceXShares2 is bytes32;

function cast(BalanceXShares2 x) pure returns (uint512) {
    return uint512.wrap(BalanceXShares2.unwrap(x));
}

function cast2(uint512 x) pure returns (BalanceXShares2) {
    return BalanceXShares2.wrap(uint512.unwrap(x));
}

function alloc() pure returns (BalanceXShares2) {
    return cast2(baseAlloc());
}

function tmp() pure returns (BalanceXShares2) {
    return cast2(baseTmp());
}

library BalanceXShares2Arithmetic {
    function omul(BalanceXShares2 r, BalanceXShares x, Shares s) internal pure returns (BalanceXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function omul(BalanceXShares2 r, Shares s, BalanceXShares x) internal pure returns (BalanceXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function div(BalanceXShares2 n, BalanceXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast(d)));
    }
}

using BalanceXShares2Arithmetic for BalanceXShares2 global;
