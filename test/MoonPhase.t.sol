// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MoonPhase} from "src/core/MoonPhase.sol";
import {BasisPoints} from "src/types/BasisPoints.sol";

import {Test} from "@forge-std/Test.sol";

contract MoonPhaseTest is Test {
    function testEpoch() external {
        vm.warp(1740721485);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 5000);
    }

    function testFullMoonAfterEpoch() external {
        vm.warp(1740721485 + 1275721);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 1);
    }

    function test2026NewMoon() external {
        vm.warp(1768783914);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 5000);
    }

    function test2026FullMoon() external {
        vm.warp(1798093689 + 43200);
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 1);
    }

    function test2027FirstQuarterMoon() external {
        vm.warp(1800063267 - 43200);
        uint256 beforePhase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        vm.warp(1800063267 + 43200);
        uint256 afterPhase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        assertGe(beforePhase, 2500);
        assertLe(afterPhase, 2500);
    }

    // This test fails because the actual moon according to the ephemeris
    // exhibits significant short-term variation on this date.
    function testFail2027LastQuarterMoon() external {
        vm.warp(1801238124 - 43200);
        uint256 beforePhase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        vm.warp(1801238124 + 43200);
        uint256 afterPhase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        assertGe(beforePhase, 2500);
        assertLe(afterPhase, 2500);
    }

    function test100Years() external {
        vm.warp(4896849194); // This is the first new moon 100 years after the epoch
        assertEq(BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp())), 5000);
    }

    function testRange(uint256 time) external {
        time = bound(time, 1735597605, 64849501605);
        vm.warp(time);
        uint256 phase = BasisPoints.unwrap(MoonPhase.moonPhase(vm.getBlockTimestamp()));
        assertGe(phase, 1);
        assertLe(phase, 5000);
    }
}
