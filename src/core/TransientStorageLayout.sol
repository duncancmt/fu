// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract TransientStorageLayout {
    function _setTemporaryAllowance(
        mapping(address => mapping(address => uint256)) storage temporaryAllowance,
        address owner,
        address spender,
        uint256 amount
    ) internal {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(0x20, temporaryAllowance.slot)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            tstore(keccak256(0x00, 0x40), amount)
        }
    }

    function _getTemporaryAllowance(
        mapping(address => mapping(address => uint256)) storage temporaryAllowance,
        address owner,
        address spender
    ) internal view returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(0x20, temporaryAllowance.slot)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            r := tload(keccak256(0x00, 0x40))
        }
    }
}
