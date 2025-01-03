// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "./BasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";
import {Ternary} from "../lib/Ternary.sol";

/// This type is given as `uint256` for efficiency, but it is capped at `2 ** 177 - 1`.
type Shares is uint256;

Shares constant ZERO = Shares.wrap(0);
Shares constant ONE = Shares.wrap(1);

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
        unchecked {
            return Shares.wrap(Shares.unwrap(x) * y);
        }
    }

    function div(Shares n, uint256 d) internal pure returns (Shares) {
        // TODO: see if this can use `unsafeDiv`
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

function ternary(bool c, Shares x, Shares y) pure returns (Shares) {
    return Shares.wrap(Ternary.ternary(c, Shares.unwrap(x), Shares.unwrap(y)));
}

// This is the same as `Shares`, except it has padding on both ends, just to make life harder for
// people who do state overrides. Also, unlike "normal" Solidity behavior, dirty padding is not
// cleaned, but instead results in the entire slot being implicitly cleared.
type SharesStorage is uint256;

function load(SharesStorage x) pure returns (Shares r) {
    assembly ("memory-safe") {
        r := mul(shr(0x28, x), iszero(and(0xffffffffff00000000000000000000000000000000000000000000ffffffffff, x)))
    }
}

function store(Shares x) pure returns (SharesStorage r) {
    assembly ("memory-safe") {
        r := shl(0x28, x)
    }
}

using {load} for SharesStorage global;
using {store} for Shares global;
