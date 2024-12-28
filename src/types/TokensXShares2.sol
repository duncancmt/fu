// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {Tokens} from "./Tokens.sol";
import {TokensXShares, cast} from "./TokensXShares.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../lib/512Math.sol";

type TokensXShares2 is bytes32;

function cast(TokensXShares2 x) pure returns (uint512) {
    return uint512.wrap(TokensXShares2.unwrap(x));
}

function cast2(uint512 x) pure returns (TokensXShares2) {
    return TokensXShares2.wrap(uint512.unwrap(x));
}

function alloc() pure returns (TokensXShares2) {
    return cast2(baseAlloc());
}

function tmp() pure returns (TokensXShares2) {
    return cast2(baseTmp());
}

library TokensXShares2Arithmetic {
    function oadd(TokensXShares2 r, TokensXShares2 x, TokensXShares2 y) internal pure returns (TokensXShares2) {
        return cast2(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(TokensXShares2 r, TokensXShares2 x, TokensXShares2 y) internal pure returns (TokensXShares2) {
        return cast2(cast(r).osub(cast(x), cast(y)));
    }

    function omul(TokensXShares2 r, TokensXShares x, Shares s) internal pure returns (TokensXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function omul(TokensXShares2 r, Shares s, TokensXShares x) internal pure returns (TokensXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function div(TokensXShares2 n, TokensXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast(d)));
    }

    function divMulti(TokensXShares2 n0, TokensXShares2 n1, TokensXShares d) internal view returns (Shares, Shares) {
        (uint256 r0, uint256 r1) = cast(n0).divMulti(cast(n1), cast(d));
        return (Shares.wrap(r0), Shares.wrap(r1));
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
