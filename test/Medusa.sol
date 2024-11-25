// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "src/core/types/BasisPoints.sol";
import {Shares} from "src/core/types/Shares.sol";
import {Balance} from "src/core/types/Balance.sol";

import {ReflectMathTest} from "./ReflectMath.t.sol";

import {Boilerplate, MedusaBoilerplate} from "./Boilerplate.sol";
import {StdAssertions} from "@forge-std/StdAssertions.sol";

contract MedusaReflectMathTest is ReflectMathTest, MedusaBoilerplate {
    function testTransfer_(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Balance amount,
        BasisPoints feeRate/*,
        uint256 sharesRatio*/
    ) external {
        super.testTransfer(totalSupply, totalShares, fromShares, toShares, amount, feeRate);
        assert(!failed());
    }

    function testTransferAll_(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints feeRate/*,
        uint256 sharesRatio*/
    ) external {
        super.testTransferAll(totalSupply, totalShares, fromShares, toShares, feeRate);
        assert(!failed());
    }

    function testDeliver_(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Balance amount/*,
        uint256 sharesRatio*/
    ) external {
        super.testDeliver(totalSupply, totalShares, fromShares, amount);
        assert(!failed());
    }

    // solc inheritance is so stupid
    function setUp() public pure override(Boilerplate, MedusaBoilerplate) {
        return super.setUp();
    }

    function assume(bool condition) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.assume(condition);
    }

    function assertTrue(bool data) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertTrue(data);
    }

    function assertTrue(bool data, string memory err) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertTrue(data, err);
    }

    function assertEq(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertEq(left, right);
    }

    function assertEq(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertEq(left, right, err);
    }

    function assertLt(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertLt(left, right);
    }

    function assertLt(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertLt(left, right, err);
    }

    function assertGt(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertGt(left, right);
    }

    function assertGt(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertGt(left, right, err);
    }

    function assertNotEq(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertNotEq(left, right);
    }

    function assertNotEq(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertNotEq(left, right, err);
    }

    function assertLe(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertLe(left, right);
    }

    function assertLe(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertLe(left, right, err);
    }

    function assertGe(uint256 left, uint256 right) internal pure override(MedusaBoilerplate, StdAssertions) {
        return super.assertGe(left, right);
    }

    function assertGe(uint256 left, uint256 right, string memory err)
        internal
        pure
        override(MedusaBoilerplate, StdAssertions)
    {
        return super.assertGe(left, right, err);
    }
}
