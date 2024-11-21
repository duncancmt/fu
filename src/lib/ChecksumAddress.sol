// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

library ChecksumAddress {
    /// Adapted from Solady https://github.com/Vectorized/solady/blob/1dd8967b93b379ca6cf384640e0715e55ef08e3d/src/utils/g/LibString.sol#L334
    function toChecksumAddress(address addr) internal pure returns (string memory r) {
        assembly ("memory-safe") {
            r := mload(0x40)
            mstore(0x40, add(r, 0x60))
            mstore(0x0f, 0x30313233343536373839616263646566) // "0123456789abcdef" lookup table

            mstore(add(0x02, r), 0x3078) // "0x" prefix
            mstore(r, 0x2a) // length

            addr := shl(0x60, addr)
            let o := add(0x22, r)
            for { let i } true {} {
                let p := add(o, add(i, i))
                let temp := byte(i, addr)
                mstore8(add(0x01, p), mload(and(0x0f, temp)))
                mstore8(p, mload(shr(0x04, temp)))
                i := add(i, 0x01)
                if eq(i, 0x14) { break }
            }
            let mask := 0x4040404040404040404040404040404040404040404040404040404040404040
            let hash := and(0x8888888888888888888888888888888888888888888888888888888888888880, keccak256(o, 0x28))
            for { let i } true {} {
                mstore(add(i, i), mul(0x88000000000000000000000000000000000000000000000000000000000000, byte(i, hash)))
                i := add(i, 0x01)
                if eq(i, 0x14) { break }
            }
            mstore(o, xor(mload(o), shr(0x01, and(mload(0x00), and(mload(o), mask)))))
            o := add(o, 0x20)
            mstore(o, xor(mload(o), shr(0x01, and(mload(0x20), and(mload(o), mask)))))
        }
    }
}
