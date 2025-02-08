// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Tokens} from "./Tokens.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is actually only 159 bits.
type TokensXBasisPoints is uint256;

function scale(Tokens s, BasisPoints bp) pure returns (TokensXBasisPoints) {
    unchecked {
        return TokensXBasisPoints.wrap(Tokens.unwrap(s) * BasisPoints.unwrap(bp));
    }
}

function cast(TokensXBasisPoints tbp) pure returns (Tokens) {
    return Tokens.wrap(UnsafeMath.unsafeDiv(TokensXBasisPoints.unwrap(tbp), BasisPoints.unwrap(BASIS)));
}

function castUp(TokensXBasisPoints tbp) pure returns (Tokens) {
    return Tokens.wrap(UnsafeMath.unsafeDivUp(TokensXBasisPoints.unwrap(tbp), BasisPoints.unwrap(BASIS)));
}

library TokensXBasisPointsArithmetic {
    using UnsafeMath for uint256;

    function mul(TokensXBasisPoints x, uint256 y) internal pure returns (TokensXBasisPoints) {
        unchecked {
            return TokensXBasisPoints.wrap(TokensXBasisPoints.unwrap(x) * y);
        }
    }

    function div(TokensXBasisPoints n, uint256 d) internal pure returns (TokensXBasisPoints) {
        return TokensXBasisPoints.wrap(TokensXBasisPoints.unwrap(n).unsafeDiv(d));
    }
}

using TokensXBasisPointsArithmetic for TokensXBasisPoints global;

function __add(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (TokensXBasisPoints) {
    unchecked {
        return TokensXBasisPoints.wrap(TokensXBasisPoints.unwrap(a) + TokensXBasisPoints.unwrap(b));
    }
}

function __sub(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (TokensXBasisPoints) {
    unchecked {
        return TokensXBasisPoints.wrap(TokensXBasisPoints.unwrap(a) - TokensXBasisPoints.unwrap(b));
    }
}

function __eq(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) == TokensXBasisPoints.unwrap(b);
}

function __lt(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) < TokensXBasisPoints.unwrap(b);
}

function __gt(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) > TokensXBasisPoints.unwrap(b);
}

function __ne(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) != TokensXBasisPoints.unwrap(b);
}

function __le(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) <= TokensXBasisPoints.unwrap(b);
}

function __ge(TokensXBasisPoints a, TokensXBasisPoints b) pure returns (bool) {
    return TokensXBasisPoints.unwrap(a) >= TokensXBasisPoints.unwrap(b);
}

using {
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=
} for TokensXBasisPoints global;
