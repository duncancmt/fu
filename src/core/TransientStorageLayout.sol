// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CrazyBalance} from "../types/CrazyBalance.sol";

abstract contract TransientStorageLayout {
    function _setTemporaryAllowance(
        mapping(address => mapping(address => CrazyBalance)) storage temporaryAllowance,
        address owner,
        address spender,
        CrazyBalance amount
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
        mapping(address => mapping(address => CrazyBalance)) storage temporaryAllowance,
        address owner,
        address spender
    ) internal view returns (CrazyBalance r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(0x20, temporaryAllowance.slot)
            mstore(0x20, keccak256(0x00, 0x40))
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            r := tload(keccak256(0x00, 0x40))
        }
    }
}
