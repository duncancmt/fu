// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MoonPhase} from "src/core/MoonPhase.sol";
import {BasisPoints} from "src/types/BasisPoints.sol";

import {Test} from "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

contract MoonPhaseTest is Test {
    function testEpoch() external {
        vm.warp(1740721485);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 5000);
    }

    function testFullMoonAfterEpoch() external {
        vm.warp(1740721485 + 1275721);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 1);
    }

    function testRange(uint256 time) external {
        time = bound(time, 1735597605, 64849501605);
        vm.warp(time);
        uint256 phase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        assertGe(phase, 1);
        assertLe(phase, 5000);
    }
}
