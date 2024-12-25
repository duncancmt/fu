// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CrazyBalance} from "../types/CrazyBalance.sol";

abstract contract TransientStorageLayout {
    function _setTemporaryAllowance(
        address owner,
        address spender,
        CrazyBalance amount
    ) internal {
        assembly ("memory-safe") {
            mstore(0x14, spender)
            mstore(0x00, owner)
            tstore(keccak256(0x0c, 0x28), amount)
        }
    }

    function _getTemporaryAllowance(
        address owner,
        address spender
    ) internal view returns (CrazyBalance r) {
        assembly ("memory-safe") {
            mstore(0x14, spender)
            mstore(0x00, owner)
            r := tload(keccak256(0x0c, 0x28))
        }
    }
}
