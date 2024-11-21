// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ChecksumAddress} from "src/lib/ChecksumAddress.sol";

import {Test} from "@forge-std/Test.sol";

contract ChecksumAddressTest is Test {
    using ChecksumAddress for address;

    function testDead() external pure {
        string memory checksummed = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD.toChecksumAddress();
        assertEq(checksummed, "0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD");
    }

    function testDuncancmtDotEth() external pure {
        string memory checksummed = 0xD6B66609E5C05210BE0A690aB3b9788BA97aFa60.toChecksumAddress();
        assertEq(checksummed, "0xD6B66609E5C05210BE0A690aB3b9788BA97aFa60");
    }

    function testWeth() external pure {
        string memory checksummed = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.toChecksumAddress();
        assertEq(checksummed, "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    }
}
