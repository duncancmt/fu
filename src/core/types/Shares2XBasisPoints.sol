// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "./BasisPoints.sol";
import {Shares} from "./Shares.sol";
import {SharesXBasisPoints} from "./SharesXBasisPoints.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../../lib/512Math.sol";

type Shares2XBasisPoints is bytes32;

function cast(Shares2XBasisPoints x) pure returns (uint512) {
    return uint512.wrap(Shares2XBasisPoints.unwrap(x));
}

function cast(uint512 x) pure returns (Shares2XBasisPoints) {
    return Shares2XBasisPoints.wrap(uint512.unwrap(x));
}

function alloc() pure returns (Shares2XBasisPoints) {
    return cast(baseAlloc());
}

function tmp() pure returns (Shares2XBasisPoints) {
    return cast(baseTmp());
}

library Shares2XBasisPointsArithmetic {
    function oadd(Shares2XBasisPoints r, Shares2XBasisPoints x, Shares2XBasisPoints y) internal pure returns (Shares2XBasisPoints) {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(Shares2XBasisPoints r, Shares2XBasisPoints x, Shares2XBasisPoints y) internal pure returns (Shares2XBasisPoints) {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(Shares2XBasisPoints r, SharesXBasisPoints sbp, Shares s)
        internal
        pure
        returns (Shares2XBasisPoints)
    {
        return cast(cast(r).omul(SharesXBasisPoints.unwrap(sbp), Shares.unwrap(s)));
    }

    function omul(Shares2XBasisPoints r, Shares s, SharesXBasisPoints sbp)
        internal
        pure
        returns (Shares2XBasisPoints)
    {
        return cast(cast(r).omul(Shares.unwrap(s), SharesXBasisPoints.unwrap(sbp)));
    }

    function div(Shares2XBasisPoints n, SharesXBasisPoints d) internal pure returns (Shares) {
        return Shares.wrap(cast(n).div(SharesXBasisPoints.unwrap(d)));
    }

    function div(Shares2XBasisPoints n, Shares d) internal pure returns (SharesXBasisPoints) {
        return SharesXBasisPoints.wrap(cast(n).div(Shares.unwrap(d)));
    }
}

using Shares2XBasisPointsArithmetic for Shares2XBasisPoints global;

function __eq(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) == cast(b);
}

function __lt(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) < cast(b);
}

function __gt(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) > cast(b);
}

function __ne(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) != cast(b);
}

function __le(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) <= cast(b);
}

function __ge(Shares2XBasisPoints a, Shares2XBasisPoints b) pure returns (bool) {
    return cast(a) >= cast(b);
}

using {__eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=} for Shares2XBasisPoints global;
