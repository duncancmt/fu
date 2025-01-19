// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library QuickSort {
    function quickSort(address[] memory a) internal pure {
        assembly ("memory-safe") {
            function recur(lo, hi) {
                if lt(lo, hi) {
                    let mid := lo
                    {
                        let x := mload(hi)
                        for { let i := lo } lt(i, hi) { i := add(0x20, i) } {
                            let y := mload(i)
                            if iszero(gt(y, x)) {
                                mstore(i, mload(mid))
                                mstore(mid, y)
                                mid := add(0x20, mid)
                            }
                        }
                        mstore(hi, mload(mid))
                        mstore(mid, x)
                    }

                    // `sub(mid, 0x20)` can't underflow because the linear array we sort is always
                    // prefixed with 1 word (its length)
                    recur(lo, sub(mid, 0x20))
                    recur(add(0x20, mid), hi)
                }
            }

            recur(add(0x20, a), add(shl(0x05, mload(a)), a))
        }
    }
}
