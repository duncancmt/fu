// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Tokens} from "./Tokens.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is actually only 158 bits.
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

using {__add as +, __sub as -} for TokensXBasisPoints global;
