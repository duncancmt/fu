// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Ternary {
    function ternary(bool c, uint256 x, uint256 y) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := xor(y, mul(xor(x, y), c))
        }
    }

    function ternary(bool c, int256 x, int256 y) internal pure returns (int256 r) {
        assembly ("memory-safe") {
            r := xor(y, mul(xor(x, y), c))
        }
    }

    function swap(bool c, uint256 x, uint256 y) internal pure returns (uint256 a, uint256 b) {
        assembly ("memory-safe") {
            let t := mul(xor(x, y), c)
            a := xor(x, t)
            b := xor(y, t)
        }
    }
}
