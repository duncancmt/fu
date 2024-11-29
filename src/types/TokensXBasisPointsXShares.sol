// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {Tokens} from "./Tokens.sol";
import {SharesXBasisPoints} from "./SharesXBasisPoints.sol";
import {TokensXBasisPoints} from "./TokensXBasisPoints.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../lib/512Math.sol";

type TokensXBasisPointsXShares is bytes32;

function cast(TokensXBasisPointsXShares x) pure returns (uint512) {
    return uint512.wrap(TokensXBasisPointsXShares.unwrap(x));
}

function cast(uint512 x) pure returns (TokensXBasisPointsXShares) {
    return TokensXBasisPointsXShares.wrap(uint512.unwrap(x));
}

function alloc() pure returns (TokensXBasisPointsXShares) {
    return cast(baseAlloc());
}

function tmp() pure returns (TokensXBasisPointsXShares) {
    return cast(baseTmp());
}

library TokensXBasisPointsXSharesArithmetic {
    function oadd(TokensXBasisPointsXShares r, TokensXBasisPointsXShares x, TokensXBasisPointsXShares y)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(TokensXBasisPointsXShares r, TokensXBasisPointsXShares x, TokensXBasisPointsXShares y)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(TokensXBasisPointsXShares r, Tokens b, SharesXBasisPoints s)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).omul(Tokens.unwrap(b), SharesXBasisPoints.unwrap(s)));
    }

    function omul(TokensXBasisPointsXShares r, SharesXBasisPoints s, Tokens b)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).omul(SharesXBasisPoints.unwrap(s), Tokens.unwrap(b)));
    }

    function omul(TokensXBasisPointsXShares r, Shares s, TokensXBasisPoints b)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).omul(Shares.unwrap(s), TokensXBasisPoints.unwrap(b)));
    }

    function omul(TokensXBasisPointsXShares r, TokensXBasisPoints b, Shares s)
        internal
        pure
        returns (TokensXBasisPointsXShares)
    {
        return cast(cast(r).omul(TokensXBasisPoints.unwrap(b), Shares.unwrap(s)));
    }
}

using TokensXBasisPointsXSharesArithmetic for TokensXBasisPointsXShares global;
