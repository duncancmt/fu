// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {QuickSort} from "script/QuickSort.sol";

import {Test} from "@forge-std/Test.sol";

contract QuickSortTest is Test {
    using QuickSort for address[];

    mapping(address => bool) internal seen;

    function testQuickSort() external {
        address[] memory a = new address[](3);
        a[0] = address(3);
        a[1] = address(2);
        a[2] = address(1);
        testQuickSort(a);
    }

    function testQuickSort(address[] memory x) public {
        address[] memory y = new address[](x.length);
        {
            uint256 j;
            for (uint256 i; i < x.length; i++) {
                address a = x[i];
                if (seen[a]) {
                    continue;
                }
                seen[a] = true;
                y[j++] = a;
            }
            assembly ("memory-safe") {
                mstore(y, j)
            }

            y.quickSort();
            assertEq(y.length, j);
        }

        if (y.length == 0) {
            return;
        }

        address prev = y[0];
        for (uint256 i = 1; i < y.length; i++) {
            address a = y[i];
            assertTrue(a > prev);
            prev = a;
        }
    }
}
