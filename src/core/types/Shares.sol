// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "./BasisPoints.sol";

import {UnsafeMath} from "../../lib/UnsafeMath.sol";

type Shares is uint256;

function scale(Shares a, BasisPoints bp) pure returns (Shares) {
    unchecked {
        return Shares.wrap(Shares.unwrap(a) * BasisPoints.unwrap(bp));
    }
}

library SharesUnsafeMathAdapter {
    using UnsafeMath for uint256;

    function inc(Shares x, bool c) internal pure returns (Shares) {
        return Shares.wrap(Shares.unwrap(x).unsafeInc(c));
    }

    function dec(Shares x, bool c) internal pure returns (Shares) {
        return Shares.wrap(Shares.unwrap(x).unsafeDec(c));
    }
}

using SharesUnsafeMathAdapter for Shares global;

library SharesArithmetic {
    function mul(Shares x, uint256 y) internal pure returns (Shares) {
        return Shares.wrap(Shares.unwrap(x) * y);
    }

    function div(Shares n, uint256 d) internal pure returns (Shares) {
        return Shares.wrap(Shares.unwrap(n) / d);
    }
}

using SharesArithmetic for Shares global;

function __add(Shares a, Shares b) pure returns (Shares) {
    unchecked {
        return Shares.wrap(Shares.unwrap(a) + Shares.unwrap(b));
    }
}

function __sub(Shares a, Shares b) pure returns (Shares) {
    unchecked {
        return Shares.wrap(Shares.unwrap(a) - Shares.unwrap(b));
    }
}

function __eq(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) == Shares.unwrap(b);
}

function __lt(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) < Shares.unwrap(b);
}

function __gt(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) > Shares.unwrap(b);
}

function __ne(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) != Shares.unwrap(b);
}

function __le(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) <= Shares.unwrap(b);
}

function __ge(Shares a, Shares b) pure returns (bool) {
    return Shares.unwrap(a) >= Shares.unwrap(b);
}

using {
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __gt as >=
} for Shares global;
