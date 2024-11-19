// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library Settings {
    uint8 internal constant DECIMALS = 36;
    uint256 internal constant INITIAL_SUPPLY = uint256(type(uint112).max) * type(uint40).max;
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 20;
}
