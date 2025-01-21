// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "src/types/BasisPoints.sol";
import {Shares} from "src/types/Shares.sol";
import {Tokens} from "src/types/Tokens.sol";
import {Votes} from "src/types/Votes.sol";

import {ReflectMathTest} from "./ReflectMath.t.sol";
import {CheckpointsTest} from "./Checkpoints.t.sol";
import {FUTest} from "./FU.t.sol";

import {Boilerplate, MedusaBoilerplate} from "./Boilerplate.sol";
import {StdAssertions} from "@forge-std/StdAssertions.sol";

contract MedusaFUTest is MedusaBoilerplate, FUTest {
    constructor() {
        super.deployFu();
    }

    function setUp() public view override(MedusaBoilerplate, FUTest) {
        assume(targetContracts().length == 0);
        return smuggle(super.setUp)();
    }

    function deployFuDependencies() internal override {
        return deployFuDependenciesMedusa();
    }

    // solc inheritance is so stupid
    function assume(bool condition) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.assume(condition);
    }

    function label(address target, string memory name) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.label(target, name);
    }

    function assertTrue(bool condition) internal pure override(MedusaBoilerplate, StdAssertions) {
        super.assertTrue(condition);
    }

    function assertTrue(bool condition, string memory err) internal pure override(MedusaBoilerplate, StdAssertions) {
        super.assertTrue(condition, err);
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
}

contract MedusaReflectMathTest is ReflectMathTest, MedusaBoilerplate {
    function testTransferSome(Tokens, Shares, Shares, Shares, Tokens, BasisPoints, uint256) public view override {
        return;
    }

    function testTransferAll(Tokens, Shares, Shares, Shares, BasisPoints, uint256) public pure override {
        return;
    }

    function testDeliver(Tokens, Shares, Shares, Tokens, uint256) public view override {
        return;
    }

    function medusa_testTransferSome(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) external {
        super.testTransferSome(totalSupply, totalShares, fromShares, toShares, amount, taxRate, sharesRatio);
        assert(!failed());
    }

    function medusa_testTransferAll(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) external {
        super.testTransferAll(totalSupply, totalShares, fromShares, toShares, taxRate, sharesRatio);
        assert(!failed());
    }

    function medusa_testDeliver(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Tokens amount,
        uint256 sharesRatio
    ) external {
        super.testDeliver(totalSupply, totalShares, fromShares, amount, sharesRatio);
        assert(!failed());
    }

    // solc inheritance is so stupid
    function setUp() public override(Boilerplate, MedusaBoilerplate) {
        return super.setUp();
    }

    function assume(bool condition) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.assume(condition);
    }

    function label(address target, string memory name) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.label(target, name);
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

contract MedusaCheckpointsTest is CheckpointsTest, MedusaBoilerplate {
    function property_total() external view returns (bool) {
        super.invariant_total();
        return !failed();
    }

    function property_actors() external view returns (bool) {
        super.invariant_actors();
        return !failed();
    }

    function property_totalActors() external view returns (bool) {
        super.invariant_totalactors();
        return !failed();
    }

    function invariant_total() public pure override {
        return;
    }

    function invariant_actors() public pure override {
        return;
    }

    function invariant_totalactors() public pure override {
        return;
    }

    function mint(address to, Votes incr, uint32 elapsed) public override {
        super.mint(to, incr, elapsed);
        assert(!failed());
    }

    function mint(address to, Votes incr) public override {
        super.mint(to, incr);
        assert(!failed());
    }

    function burn(uint256 fromActor, Votes decr, uint32 elapsed) public override {
        super.burn(fromActor, decr, elapsed);
        assert(!failed());
    }

    function burn(uint256 fromActor, Votes decr) public override {
        super.burn(fromActor, decr);
        assert(!failed());
    }

    function transfer(uint256 fromActor, address to, Votes incr, Votes decr, uint32 elapsed) public override {
        super.transfer(fromActor, to, incr, decr, elapsed);
        assert(!failed());
    }

    function transfer(uint256 fromActor, address to, Votes incr, Votes decr) public override {
        super.transfer(fromActor, to, incr, decr);
        assert(!failed());
    }

    // solc inheritance is so stupid
    function setUp() public view override(MedusaBoilerplate, CheckpointsTest) {
        assume(targetContracts().length == 0);
        return smuggle(super.setUp)();
    }

    function assume(bool condition) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.assume(condition);
    }

    function label(address target, string memory name) internal pure override(Boilerplate, MedusaBoilerplate) {
        return super.label(target, name);
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
