// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares} from "./Shares.sol";
import {Tokens} from "./Tokens.sol";

import {uint512, tmp as baseTmp, alloc as baseAlloc} from "../lib/512Math.sol";

type TokensXShares is bytes32;

function cast(TokensXShares x) pure returns (uint512) {
    return uint512.wrap(TokensXShares.unwrap(x));
}

function cast(uint512 x) pure returns (TokensXShares) {
    return TokensXShares.wrap(uint512.unwrap(x));
}

function alloc() pure returns (TokensXShares) {
    return cast(baseAlloc());
}

function tmp() pure returns (TokensXShares) {
    return cast(baseTmp());
}

library TokensXSharesArithmetic {
    function oadd(TokensXShares r, TokensXShares x, TokensXShares y) internal pure returns (TokensXShares) {
        return cast(cast(r).oadd(cast(x), cast(y)));
    }

    function osub(TokensXShares r, TokensXShares x, TokensXShares y) internal pure returns (TokensXShares) {
        return cast(cast(r).osub(cast(x), cast(y)));
    }

    function omul(TokensXShares r, Tokens b, Shares s) internal pure returns (TokensXShares) {
        return cast(cast(r).omul(Tokens.unwrap(b), Shares.unwrap(s)));
    }

    function omul(TokensXShares r, Shares s, Tokens b) internal pure returns (TokensXShares) {
        return cast(cast(r).omul(Shares.unwrap(s), Tokens.unwrap(b)));
    }

    function div(TokensXShares n, Tokens d) internal pure returns (Shares) {
        return Shares.wrap(cast(n).div(Tokens.unwrap(d)));
    }

    function div(TokensXShares n, Shares d) internal pure returns (Tokens) {
        return Tokens.wrap(cast(n).div(Shares.unwrap(d)));
    }

    function divMulti(TokensXShares n0, TokensXShares n1, Tokens d) internal pure returns (Shares, Shares) {
        (uint256 r0, uint256 r1) = cast(n0).divMulti(cast(n1), Tokens.unwrap(d));
        return (Shares.wrap(r0), Shares.wrap(r1));
    }

    function divMulti(TokensXShares n0, TokensXShares n1, Shares d) internal pure returns (Tokens, Tokens) {
        (uint256 r0, uint256 r1) = cast(n0).divMulti(cast(n1), Shares.unwrap(d));
        return (Tokens.wrap(r0), Tokens.wrap(r1));
    }
}

using TokensXSharesArithmetic for TokensXShares global;

function __eq(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) == cast(b);
}

function __lt(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) < cast(b);
}

function __gt(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) > cast(b);
}

function __ne(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) != cast(b);
}

function __le(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) <= cast(b);
}

function __ge(TokensXShares a, TokensXShares b) pure returns (bool) {
    return cast(a) >= cast(b);
}

using {__eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=} for TokensXShares global;

library SharesToTokens {
    function toTokens(Shares shares, Tokens totalSupply, Shares totalShares) internal pure returns (Tokens) {
        return tmp().omul(shares, totalSupply).div(totalShares);
    }

    function toTokensMulti(Shares shares0, Shares shares1, Tokens totalSupply, Shares totalShares) internal pure returns (Tokens r0, Tokens r1) {
        uint256 freePtr;
        assembly ("memory-safe") {
            freePtr := mload(0x40)
        }

        TokensXShares n0 = alloc().omul(shares0, totalSupply);
        TokensXShares n1 = tmp().omul(shares1, totalSupply);
        (r0, r1) = n0.divMulti(n1, totalShares);

        assembly ("memory-safe") {
            mstore(0x40, freePtr)
        }
    }

    function toTokensUp(Shares shares, Tokens totalSupply, Shares totalShares) internal pure returns (Tokens r) {
        uint256 freePtr;
        assembly ("memory-safe") {
            freePtr := mload(0x40)
        }

        TokensXShares n = alloc().omul(shares, totalSupply);
        r = n.div(totalShares);
        r = r.inc(tmp().omul(r, totalShares) < n);

        assembly ("memory-safe") {
            mstore(0x40, freePtr)
        }
    }
}
