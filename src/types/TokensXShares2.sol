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
    function omul(TokensXShares2 r, TokensXShares x, Shares s) internal pure returns (TokensXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function omul(TokensXShares2 r, Shares s, TokensXShares x) internal pure returns (TokensXShares2) {
        return cast2(cast(r).omul(cast(x), Shares.unwrap(s)));
    }

    function div(TokensXShares2 n, TokensXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast(d)));
    }
}

using TokensXShares2Arithmetic for TokensXShares2 global;
