// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {QuickSort} from "script/QuickSort.sol";

import {Test} from "@forge-std/Test.sol";

contract QuickSortTest is Test {
    using QuickSort for address[];

    mapping(address => uint256) internal count;

    function testQuickSort() external {
        address[] memory a = new address[](3);
        a[0] = address(3);
        a[1] = address(2);
        a[2] = address(1);
        testQuickSort(a);
    }

    function testQuickSort(address[] memory a) public {
        uint256 length = a.length;
        for (uint256 i; i < length; i++) {
            count[a[i]]++;
        }
        a.quickSort();
        assertEq(a.length, length);

        if (a.length == 0) {
            return;
        }

        // By the pigeonhole principle, the check that the length is unmodified and the underflow
        // checks on `--` together ensure that the contents of `a` is unmodified, only the order.
        address prev = a[0];
        count[prev]--;
        for (uint256 i = 1; i < length; i++) {
            address x = a[i];
            count[x]--;
            assertTrue(x >= prev);
            prev = x;
        }
    }
}
