// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UnsafeMath} from "../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is capped at 10_000
/// (14 bits).
type BasisPoints is uint256;

BasisPoints constant ZERO = BasisPoints.wrap(0);
BasisPoints constant BASIS = BasisPoints.wrap(10_000);

library BasisPointsArithmetic {
    using UnsafeMath for uint256;

    function mul(BasisPoints x, uint256 y) internal pure returns (BasisPoints) {
        unchecked {
            return BasisPoints.wrap(BasisPoints.unwrap(x) * y);
        }
    }

    function div(BasisPoints n, uint256 d) internal pure returns (BasisPoints) {
        return BasisPoints.wrap(BasisPoints.unwrap(n).unsafeDiv(d));
    }
}

using BasisPointsArithmetic for BasisPoints global;

function __sub(BasisPoints a, BasisPoints b) pure returns (BasisPoints) {
    unchecked {
        return BasisPoints.wrap(BasisPoints.unwrap(a) - BasisPoints.unwrap(b));
    }
}

using {__sub as -} for BasisPoints global;

function __eq(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) == BasisPoints.unwrap(b);
}

function __lt(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) < BasisPoints.unwrap(b);
}

function __gt(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) > BasisPoints.unwrap(b);
}

function __ne(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) != BasisPoints.unwrap(b);
}

function __le(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) <= BasisPoints.unwrap(b);
}

function __ge(BasisPoints a, BasisPoints b) pure returns (bool) {
    return BasisPoints.unwrap(a) >= BasisPoints.unwrap(b);
}

using {__eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __gt as >=} for BasisPoints global;

function scale(uint256 x, BasisPoints bp) pure returns (uint256) {
    unchecked {
        return x * BasisPoints.unwrap(bp) / BasisPoints.unwrap(BASIS);
    }
}

function scaleUp(uint256 x, BasisPoints bp) pure returns (uint256) {
    unchecked {
        return UnsafeMath.unsafeDivUp(x * BasisPoints.unwrap(bp), BasisPoints.unwrap(BASIS));
    }
}
