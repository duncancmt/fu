// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {TokensXShares, cast} from "./TokensXShares.sol";

import {uint512} from "../lib/512Math.sol";

type TokensXShares2 is bytes32;

function cast(TokensXShares2 x) pure returns (uint512) {
    return uint512.wrap(TokensXShares2.unwrap(x));
}

function cast2(uint512 x) pure returns (TokensXShares2) {
    return TokensXShares2.wrap(uint512.unwrap(x));
}

library TokensXShares2Arithmetic {
    function div(TokensXShares2 n, TokensXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).divAlt(cast(d)));
    }
}

using TokensXShares2Arithmetic for TokensXShares2 global;

function __eq(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) == cast(b);
}

function __lt(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) < cast(b);
}

function __gt(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) > cast(b);
}

function __ne(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) != cast(b);
}

function __le(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) <= cast(b);
}

function __ge(TokensXShares2 a, TokensXShares2 b) pure returns (bool) {
    return cast(a) >= cast(b);
}

using {__eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=} for TokensXShares2 global;
