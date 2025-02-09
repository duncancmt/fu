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

library TokensXBasisPointsXShares2Arithmetic {
    function div(TokensXBasisPointsXShares2 n, TokensXBasisPointsXShares d) internal view returns (Shares) {
        return Shares.wrap(cast(n).div(cast2(d)));
    }

    function divMulti(TokensXBasisPointsXShares2 n0, TokensXBasisPointsXShares2 n1, TokensXBasisPointsXShares d)
        internal
        view
        returns (Shares, Shares)
    {
        (uint256 r0, uint256 r1) = cast(n0).divMulti(cast(n1), cast2(d));
        return (Shares.wrap(r0), Shares.wrap(r1));
    }
}

using TokensXBasisPointsXShares2Arithmetic for TokensXBasisPointsXShares2 global;
