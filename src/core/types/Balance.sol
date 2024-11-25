// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// This type is given as `uint256` for efficiency, but it is capped at `type(uint144).max`.
type Balance is uint256;

library BalanceArithmetic {
    function mul(Balance x, uint256 y) internal pure returns (Balance) {
        return Balance.wrap(Balance.unwrap(x) * y);
    }

    function div(Balance n, uint256 d) internal pure returns (Balance) {
        return Balance.wrap(Balance.unwrap(n) / d);
    }
}

using BalanceArithmetic for Balance global;

function __add(Balance a, Balance b) pure returns (Balance) {
    unchecked {
        return Balance.wrap(Balance.unwrap(a) + Balance.unwrap(b));
    }
}

function __sub(Balance a, Balance b) pure returns (Balance) {
    unchecked {
        return Balance.wrap(Balance.unwrap(a) - Balance.unwrap(b));
    }
}

function __eq(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) == Balance.unwrap(b);
}

function __lt(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) < Balance.unwrap(b);
}

function __gt(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) > Balance.unwrap(b);
}

function __ne(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) != Balance.unwrap(b);
}

function __le(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) <= Balance.unwrap(b);
}

function __ge(Balance a, Balance b) pure returns (bool) {
    return Balance.unwrap(a) >= Balance.unwrap(b);
}

using {
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=
} for Balance global;
