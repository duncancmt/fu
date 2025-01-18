// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

library FastTransferLib {
    function fastBalanceOf(IERC20 token, address acct) internal view returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x14, acct) // Store the `acct` argument.
            mstore(0x00, 0x70a08231000000000000000000000000) // Selector for `balanceOf(address)`, with `acct`'s padding.

            // Call and check for revert. Storing the selector with padding in memory at 0 results
            // in a start of calldata at offset 16. Calldata is 36 bytes long (4 bytes selector, 32
            // bytes argument).
            if iszero(staticcall(gas(), token, 0x10, 0x24, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We assume that `token`'s code exists and that it conforms to ERC20 (won't return
            // short calldata). We do not bother to check for either of these conditions.

            r := mload(0x00)
        }
    }

    function fastTransfer(IERC20 token, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            // Storing `amount` clobbers the upper bits of the free memory pointer, but those bits
            // can never be set without running into an OOG, so it's safe. We'll restore them to
            // zero at the end.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // Selector for `transfer(address,uint256)`, with `to`'s padding.

            // Calldata starts at offset 16 and is 68 bytes long (2 * 32 + 4). We're not checking
            // the return value, so we don't bother to copy the returndata into memory.
            if iszero(call(gas(), token, 0x00, 0x10, 0x44, 0x00, 0x00)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We assume that the token we're calling is well-behaved. We don't check that it
            // might've returned `false`.

            mstore(0x34, 0x00) // Restore the part of the free memory pointer that was overwritten.
        }
    }
}
