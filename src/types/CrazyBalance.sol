// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "../core/Settings.sol";

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Shares} from "./Shares.sol";
import {Tokens} from "./Tokens.sol";
import {tmp, alloc, SharesToTokens} from "./TokensXShares.sol";

type CrazyBalance is uint256;

library CrazyBalanceAccessors {
    function toExternal(CrazyBalance x) internal pure returns (uint256) {
        return CrazyBalance.unwrap(x);
    }

    function isMax(CrazyBalance x) internal pure returns (bool) {
        return ~CrazyBalance.unwrap(x) == 0;
    }
}

using CrazyBalanceAccessors for CrazyBalance global;

function toCrazyBalance(uint256 x) pure returns (CrazyBalance) {
    return CrazyBalance.wrap(x);
}

CrazyBalance constant ZERO = CrazyBalance.wrap(0);
CrazyBalance constant MAX = CrazyBalance.wrap(type(uint256).max);

function __add(CrazyBalance a, CrazyBalance b) pure returns (CrazyBalance) {
    unchecked {
        return CrazyBalance.wrap(CrazyBalance.unwrap(a) + CrazyBalance.unwrap(b));
    }
}

function __sub(CrazyBalance a, CrazyBalance b) pure returns (CrazyBalance) {
    unchecked {
        return CrazyBalance.wrap(CrazyBalance.unwrap(a) - CrazyBalance.unwrap(b));
    }
}

function __eq(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) == CrazyBalance.unwrap(b);
}

function __lt(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) < CrazyBalance.unwrap(b);
}

function __gt(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) > CrazyBalance.unwrap(b);
}

function __ne(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) != CrazyBalance.unwrap(b);
}

function __le(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) <= CrazyBalance.unwrap(b);
}

function __ge(CrazyBalance a, CrazyBalance b) pure returns (bool) {
    return CrazyBalance.unwrap(a) >= CrazyBalance.unwrap(b);
}

using {
    __add as +,
    __sub as -,
    __eq as ==,
    __lt as <,
    __gt as >,
    __ne as !=,
    __le as <=,
    __ge as >=
} for CrazyBalance global;

library CrazyBalanceArithmetic {
    using SharesToTokens for Shares;

    function saturatingAdd(CrazyBalance x, CrazyBalance y) internal pure returns (CrazyBalance r) {
        assembly ("memory-safe") {
            r := add(x, y)
            r := or(r, sub(0x00, lt(r, y)))
        }
    }

    function toCrazyBalance(Shares shares, address account, Tokens totalSupply, Shares totalShares)
        internal
        pure
        returns (CrazyBalance)
    {
        // slither-disable-next-line divide-before-multiply
        return CrazyBalance.wrap(
            Tokens.unwrap(
                tmp().omul(shares, totalSupply.mul(uint160(account) / Settings.ADDRESS_DIVISOR)).div(
                    totalShares.mul(Settings.CRAZY_BALANCE_BASIS)
                )
            )
        );
    }

    function toCrazyBalance(Tokens tokens, address account) internal pure returns (CrazyBalance) {
        unchecked {
            // slither-disable-next-line divide-before-multiply
            return CrazyBalance.wrap(
                Tokens.unwrap(tokens) * (uint160(account) / Settings.ADDRESS_DIVISOR) / Settings.CRAZY_BALANCE_BASIS
            );
        }
    }

    function toTokens(CrazyBalance balance, address account) internal pure returns (Tokens) {
        unchecked {
            // Checking for overflow in the multiplication is unnecessary. Checking for division by
            // zero is required.
            return Tokens.wrap(
                CrazyBalance.unwrap(balance) * Settings.CRAZY_BALANCE_BASIS
                    / (uint160(account) / Settings.ADDRESS_DIVISOR)
            );
        }
    }

    function toPairBalance(Tokens tokens) internal pure returns (CrazyBalance) {
        return CrazyBalance.wrap(Tokens.unwrap(tokens) / Settings.CRAZY_BALANCE_BASIS);
    }

    function toPairBalance(Shares shares, Tokens totalSupply, Shares totalShares)
        internal
        pure
        returns (CrazyBalance)
    {
        return CrazyBalance.wrap(
            Tokens.unwrap(shares.toTokens(totalSupply, totalShares.mul(Settings.CRAZY_BALANCE_BASIS)))
        );
    }

    function toPairTokens(CrazyBalance balance) internal pure returns (Tokens) {
        unchecked {
            return Tokens.wrap(CrazyBalance.unwrap(balance) * Settings.CRAZY_BALANCE_BASIS);
        }
    }
}

using CrazyBalanceArithmetic for CrazyBalance global;
