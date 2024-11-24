// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "./Settings.sol";

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares} from "./types/Shares.sol";
import {Balance} from "./types/Balance.sol";
import {tmp} from "./types/BalanceXShares.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";
import {tmp as baseTmp} from "../lib/512Math.sol";

type CrazyBalance is uint256;

library CrazyBalanceAccessors {
    function toExternal(CrazyBalance x) internal pure returns (uint256) {
        return CrazyBalance.unwrap(x);
    }
}

function fromExternal(uint256 x) pure returns (CrazyBalance) {
    return CrazyBalance.wrap(x);
}

using CrazyBalanceAccessors for CrazyBalance global;

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
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=
} for CrazyBalance global;

library CrazyBalanceArithmetic {
    using UnsafeMath for uint256;

    function toCrazyBalance(Shares shares, address account, Balance totalSupply, Shares totalShares) internal pure returns (CrazyBalance) {
        unchecked {
            return CrazyBalance.wrap(
                baseTmp().omul(
                    Shares.unwrap(shares),
                    Balance.unwrap(totalSupply) * (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR)
                ).div(Shares.unwrap(totalShares) * Settings.CRAZY_BALANCE_BASIS)
            );
        }
    }

    function toBalance(Shares shares, Balance totalSupply, Shares totalShares) internal pure returns (Balance) {
        return tmp().omul(shares, totalSupply).div(totalShares);
    }

    function toBalance(CrazyBalance balance, address account) internal pure returns (Balance) {
        unchecked {
            // Checking for overflow in the multiplication is unnecessary. Checking for division by
            // zero is required.
            return Balance.wrap(
                CrazyBalance.unwrap(balance) * Settings.CRAZY_BALANCE_BASIS
                    / (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR)
            );
        }
    }

    function toBalance(CrazyBalance balance, address account, BasisPoints proportion) internal pure returns (Balance) {
        unchecked {
            return Balance.wrap((CrazyBalance.unwrap(balance) * BasisPoints.unwrap(proportion) * Settings.CRAZY_BALANCE_BASIS).unsafeDivUp(BasisPoints.unwrap(BASIS) * (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR)));
        }
    }
}