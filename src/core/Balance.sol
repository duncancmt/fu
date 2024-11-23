// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

type Balance is uint256;

library BalanceAccessors {
    function toExternal(Balance x) internal pure returns (uint256) {
        return Balance.unwrap(x);
    }
}

using BalanceAccessors for Balance global;

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

using {__add as +, __sub as -, __eq as ==, __lt as <, __gt as >} for Balance global;
