// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UnsafeMath} from "../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is capped at `2 ** 145 - 1`.
type Tokens is uint256;

library TokensAccessors {
    function toExternal(Tokens x) internal pure returns (uint256) {
        return Tokens.unwrap(x);
    }
}

using TokensAccessors for Tokens global;

Tokens constant ZERO = Tokens.wrap(0);
Tokens constant ONE = Tokens.wrap(1);

library TokensUnsafeMathAdapter {
    using UnsafeMath for uint256;

    function inc(Tokens x, bool c) internal pure returns (Tokens) {
        return Tokens.wrap(Tokens.unwrap(x).unsafeInc(c));
    }

    function dec(Tokens x, bool c) internal pure returns (Tokens) {
        return Tokens.wrap(Tokens.unwrap(x).unsafeDec(c));
    }
}

using TokensUnsafeMathAdapter for Tokens global;

library TokensArithmetic {
    using UnsafeMath for uint256;

    function mul(Tokens x, uint256 y) internal pure returns (Tokens) {
        unchecked {
            return Tokens.wrap(Tokens.unwrap(x) * y);
        }
    }

    function div(Tokens n, uint256 d) internal pure returns (Tokens) {
        return Tokens.wrap(Tokens.unwrap(n).unsafeDiv(d));
    }
}

using TokensArithmetic for Tokens global;

function __add(Tokens a, Tokens b) pure returns (Tokens) {
    unchecked {
        return Tokens.wrap(Tokens.unwrap(a) + Tokens.unwrap(b));
    }
}

function __sub(Tokens a, Tokens b) pure returns (Tokens) {
    unchecked {
        return Tokens.wrap(Tokens.unwrap(a) - Tokens.unwrap(b));
    }
}

function __eq(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) == Tokens.unwrap(b);
}

function __lt(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) < Tokens.unwrap(b);
}

function __gt(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) > Tokens.unwrap(b);
}

function __ne(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) != Tokens.unwrap(b);
}

function __le(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) <= Tokens.unwrap(b);
}

function __ge(Tokens a, Tokens b) pure returns (bool) {
    return Tokens.unwrap(a) >= Tokens.unwrap(b);
}

using {
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=
} for Tokens global;
