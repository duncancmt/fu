// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TestBase} from "@forge-std/Base.sol";
import {StdAssertions} from "@forge-std/StdAssertions.sol";

abstract contract Boilerplate is TestBase {
    function setUp() public virtual {}

    function assume(bool condition) internal pure virtual {
        vm.assume(condition);
    }

    function label(address target, string memory name) internal virtual {
        vm.label(target, name);
    }
}

abstract contract MedusaBoilerplate is Boilerplate, StdAssertions {
    function setUp() public virtual override {}

    constructor() {
        super.setUp();
    }

    function assume(bool condition) internal pure virtual override {
        if (!condition) {
            assembly ("memory-safe") {
                stop()
            }
        }
    }

    function label(address, string memory) internal pure virtual override {}

    function smuggle(function () internal contraband) internal pure returns (function () internal pure smuggled) {
        assembly ("memory-safe") {
            smuggled := contraband
        }
    }

    function failPure() private pure {
        smuggle(fail)();
    }

    function assertTrue(bool data) internal pure virtual override {
        if (!data) {
            failPure();
        }
    }

    function assertTrue(bool data, string memory) internal pure virtual override {
        if (!data) {
            failPure();
        }
    }

    function assertEq(uint256 left, uint256 right) internal pure virtual override {
        if (left != right) {
            failPure();
        }
    }

    function assertEq(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left != right) {
            failPure();
        }
    }

    function assertLt(uint256 left, uint256 right) internal pure virtual override {
        if (left >= right) {
            failPure();
        }
    }

    function assertLt(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left >= right) {
            failPure();
        }
    }

    function assertGt(uint256 left, uint256 right) internal pure virtual override {
        if (left <= right) {
            failPure();
        }
    }

    function assertGt(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left <= right) {
            failPure();
        }
    }

    function assertNotEq(uint256 left, uint256 right) internal pure virtual override {
        if (left == right) {
            failPure();
        }
    }

    function assertNotEq(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left == right) {
            failPure();
        }
    }

    function assertLe(uint256 left, uint256 right) internal pure virtual override {
        if (left > right) {
            failPure();
        }
    }

    function assertLe(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left > right) {
            failPure();
        }
    }

    function assertGe(uint256 left, uint256 right) internal pure virtual override {
        if (left < right) {
            failPure();
        }
    }

    function assertGe(uint256 left, uint256 right, string memory) internal pure virtual override {
        if (left < right) {
            failPure();
        }
    }
}
