// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

abstract contract TransientStorageLayout {
    // TODO: make this part of the derived contract so that we have better control over which mapping is slot zero
    mapping (address => mapping(address => uint256)) private _temporaryAllowance;

    function _setTemporaryAllowance(address owner, address spender, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(0x20, _temporaryAllowance.slot)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            tstore(keccak256(0x00, 0x40), amount)
        }
    }

    function _getTemporaryAllowance(address owner, address spender) internal view returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(0x20, _temporaryAllowance.slot)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            r := tload(keccak256(0x00, 0x40))
        }
    }
}
