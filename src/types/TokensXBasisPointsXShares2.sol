// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {SharesXBasisPoints} from "./SharesXBasisPoints.sol";
import {TokensXShares, cast as cast1} from "./TokensXShares.sol";
import {TokensXBasisPointsXShares, cast as cast2} from "./TokensXBasisPointsXShares.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../lib/512Math.sol";

type TokensXBasisPointsXShares2 is bytes32;

function cast(TokensXBasisPointsXShares2 x) pure returns (uint512) {
    return uint512.wrap(TokensXBasisPointsXShares2.unwrap(x));
}

function cast(uint512 x) pure returns (TokensXBasisPointsXShares2) {
    return TokensXBasisPointsXShares2.wrap(uint512.unwrap(x));
}

function alloc() pure returns (TokensXBasisPointsXShares2) {
    return cast(baseAlloc());
}

function tmp() pure returns (TokensXBasisPointsXShares2) {
    return cast(baseTmp());
}

library TokensXBasisPointsXShares2Arithmetic {
    function oadd(TokensXBasisPointsXShares2 r, TokensXBasisPointsXShares2 x, TokensXBasisPointsXShares2 y)
        internal
        pure
        returns (TokensXBasisPointsXShares2)
    {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(TokensXBasisPointsXShares2 r, TokensXBasisPointsXShares2 x, TokensXBasisPointsXShares2 y)
        internal
        pure
        returns (TokensXBasisPointsXShares2)
    {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(TokensXBasisPointsXShares2 r, TokensXBasisPointsXShares x, Shares s)
        internal
        pure
        returns (TokensXBasisPointsXShares2)
    {
        return cast(cast(r).omul(cast2(x), Shares.unwrap(s)));
    }

    function omul(TokensXBasisPointsXShares2 r, TokensXShares x, SharesXBasisPoints y)
        internal
        pure
        returns (TokensXBasisPointsXShares2)
    {
        return cast(cast(r).omul(cast1(x), SharesXBasisPoints.unwrap(y)));
    }

    function div(TokensXBasisPointsXShares2 n, TokensXBasisPointsXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast2(d)));
    }
}

using TokensXBasisPointsXShares2Arithmetic for TokensXBasisPointsXShares2 global;
