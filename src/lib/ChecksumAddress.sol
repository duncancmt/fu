// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library ChecksumAddress {
    function toChecksumAddress(address addr) internal pure returns (string memory r) {
        assembly ("memory-safe") {
            r := mload(0x40)
            mstore(0x40, add(0x4a, r))
            mstore(add(0x02, r), 0x3078)
            mstore(r, 0x2a)
            let lookup := "0123456789abcdef0123456789ABCDEF"
            for {
                let i := add(0x49, r)
                let end := add(0x21, r)
                let addr_copy := addr
            } gt(i, end) {
                i := sub(i, 0x01)
                addr_copy := shr(0x04, addr_copy)
            } { mstore8(i, byte(and(0x0f, addr_copy), lookup)) }
            let hash := shr(0x5f, keccak256(add(0x22, r), 0x28))
            for {
                let i := add(0x49, r)
                let end := add(0x21, r)
            } gt(i, end) {
                i := sub(i, 0x01)
                addr := shr(0x04, addr)
                hash := shr(0x04, hash)
            } {
                let nibble := and(0x0f, addr)
                let check := and(0x10, hash)
                mstore8(i, byte(or(nibble, check), lookup))
            }
        }
    }
}
