// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

type Balance is uint256;

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
