// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// This type is given as `uint256` for efficiency, but it is capped at `type(uint144).max`.
type Tokens is uint256;

library TokensArithmetic {
    function mul(Tokens x, uint256 y) internal pure returns (Tokens) {
        // TODO: see if this can be made `unchecked`
        return Tokens.wrap(Tokens.unwrap(x) * y);
    }

    function div(Tokens n, uint256 d) internal pure returns (Tokens) {
        // TODO: see if this can use `unsafeDiv`
        return Tokens.wrap(Tokens.unwrap(n) / d);
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
