// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Hexlify {
    function hexlify(bytes32 b) internal pure returns (string memory r) {
        assembly ("memory-safe") {
            r := mload(0x40)
            mstore(0x40, add(0x60, r))
            mstore(0x0f, 0x30313233343536373839616263646566) // "0123456789abcdef" lookup table

            mstore(add(0x02, r), 0x3078) // "0x" prefix
            mstore(r, 0x42) // length

            let o := add(0x22, r)
            // Hexlify `b` and write it into the output region. This is a do..while loop.
            for { let i } true {} {
                let p := add(o, add(i, i))
                let temp := byte(i, b)
                // Split `temp` into nibbles and output the corresponding lookup table entries
                mstore8(add(0x01, p), mload(and(0x0f, temp)))
                mstore8(p, mload(shr(0x04, temp)))
                i := add(0x01, i)
                if eq(i, 0x20) { break }
            }
        }
    }
}
