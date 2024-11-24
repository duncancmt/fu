// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {Balance} from "./Balance.sol";
import {SharesXBasisPoints} from "./SharesXBasisPoints.sol";
import {BalanceXBasisPoints} from "./BalanceXBasisPoints.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../../lib/512Math.sol";

type BalanceXBasisPointsXShares is bytes32;

function cast(BalanceXBasisPointsXShares x) pure returns (uint512) {
    return uint512.wrap(BalanceXBasisPointsXShares.unwrap(x));
}

function cast(uint512 x) pure returns (BalanceXBasisPointsXShares) {
    return BalanceXBasisPointsXShares.wrap(uint512.unwrap(x));
}

function alloc() pure returns (BalanceXBasisPointsXShares) {
    return cast(baseAlloc());
}

function tmp() pure returns (BalanceXBasisPointsXShares) {
    return cast(baseTmp());
}

library BalanceXBasisPointsXSharesArithmetic {
    function oadd(BalanceXBasisPointsXShares r, BalanceXBasisPointsXShares x, BalanceXBasisPointsXShares y)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(BalanceXBasisPointsXShares r, BalanceXBasisPointsXShares x, BalanceXBasisPointsXShares y)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(BalanceXBasisPointsXShares r, Balance b, SharesXBasisPoints s)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).omul(Balance.unwrap(b), SharesXBasisPoints.unwrap(s)));
    }

    function omul(BalanceXBasisPointsXShares r, SharesXBasisPoints s, Balance b)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).omul(SharesXBasisPoints.unwrap(s), Balance.unwrap(b)));
    }

    function omul(BalanceXBasisPointsXShares r, Shares s, BalanceXBasisPoints b)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).omul(Shares.unwrap(s), BalanceXBasisPoints.unwrap(b)));
    }

    function omul(BalanceXBasisPointsXShares r, BalanceXBasisPoints b, Shares s)
        internal
        pure
        returns (BalanceXBasisPointsXShares)
    {
        return cast(cast(r).omul(BalanceXBasisPoints.unwrap(b), Shares.unwrap(s)));
    }
}

using BalanceXBasisPointsXSharesArithmetic for BalanceXBasisPointsXShares global;
