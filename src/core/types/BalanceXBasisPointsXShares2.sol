// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {SharesXBasisPoints} from "./SharesXBasisPoints.sol";
import {BalanceXShares, cast as cast1} from "./BalanceXShares.sol";
import {BalanceXBasisPointsXShares, cast as cast2} from "./BalanceXBasisPointsXShares.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../../lib/512Math.sol";

type BalanceXBasisPointsXShares2 is bytes32;

function cast(BalanceXBasisPointsXShares2 x) pure returns (uint512) {
    return uint512.wrap(BalanceXBasisPointsXShares2.unwrap(x));
}

function cast(uint512 x) pure returns (BalanceXBasisPointsXShares2) {
    return BalanceXBasisPointsXShares2.wrap(uint512.unwrap(x));
}

function alloc() pure returns (BalanceXBasisPointsXShares2) {
    return cast(baseAlloc());
}

function tmp() pure returns (BalanceXBasisPointsXShares2) {
    return cast(baseTmp());
}

library BalanceXBasisPointsXShares2Arithmetic {
    function oadd(BalanceXBasisPointsXShares2 r, BalanceXBasisPointsXShares2 x, BalanceXBasisPointsXShares2 y) internal pure returns (BalanceXBasisPointsXShares2) {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(BalanceXBasisPointsXShares2 r, BalanceXBasisPointsXShares2 x, BalanceXBasisPointsXShares2 y) internal pure returns (BalanceXBasisPointsXShares2) {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(BalanceXBasisPointsXShares2 r, BalanceXBasisPointsXShares x, Shares s) internal pure returns (BalanceXBasisPointsXShares2) {
        return cast(cast(r).omul(cast2(x), Shares.unwrap(s)));
    }

    function omul(BalanceXBasisPointsXShares2 r, BalanceXShares x, SharesXBasisPoints y) internal pure returns (BalanceXBasisPointsXShares2) {
        return cast(cast(r).omul(cast1(x), SharesXBasisPoints.unwrap(y)));
    }

    function div(BalanceXBasisPointsXShares2 n, BalanceXBasisPointsXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast2(d)));
    }
}

using BalanceXBasisPointsXShares2Arithmetic for BalanceXBasisPointsXShares2 global;
