// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Checkpoints, LibCheckpoints} from "src/core/Checkpoints.sol";

import {Votes} from "src/types/Votes.sol";

import {Test} from "@forge-std/Test.sol";
import {Boilerplate} from "./Boilerplate.sol";

contract CheckpointsTest is Boilerplate, Test {
    using LibCheckpoints for Checkpoints;

    struct Shadow {
        uint48 key;
        Votes value;
    }

    Shadow[] internal total;
    mapping(address => Shadow[]) internal each;
    Checkpoints internal dut;
    uint48 internal clock;
    mapping(address => bool) internal isRegistered;
    address[] internal actors;

    function setUp() public virtual override {
        targetContract(address(this));
        FuzzSelector memory exclusion = FuzzSelector({addr: address(this), selectors: new bytes4[](1)});
        exclusion.selectors[0] = this.setUp.selector;
        excludeSelector(exclusion);
    }

    function mint(address to, Votes incr, uint32 elapsed) public virtual {
        assume(to != address(0));
        incr = Votes.wrap(bound(Votes.unwrap(incr), 1, (2 ** 145 - 1) >> 16));
        assume(elapsed > 1);

        clock += elapsed;
        dut.mint(to, incr, clock);

        if (!isRegistered[to]) {
            actors.push(to);
            isRegistered[to] = true;
        }

        if (total.length == 0) {
            total.push(Shadow({key: clock, value: incr}));
            each[to].push(Shadow({key: clock, value: incr}));
        } else {
            total.push(Shadow({key: clock, value: total[total.length - 1].value + incr}));
            if (each[to].length == 0) {
                each[to].push(Shadow({key: clock, value: incr}));
            } else {
                each[to].push(Shadow({key: clock, value: each[to][each[to].length - 1].value + incr}));
            }
        }
    }

    function mint(address to, Votes incr) public virtual {
        assume(to != address(0));
        incr = Votes.wrap(bound(Votes.unwrap(incr), 1, (2 ** 145 - 1) >> 16));
        assume(clock != 0);

        dut.mint(to, incr, clock);

        if (!isRegistered[to]) {
            actors.push(to);
            isRegistered[to] = true;
        }

        if (total[total.length - 1].key == clock) {
            total[total.length - 1].value = total[total.length - 1].value + incr;
        } else {
            total.push(Shadow({key: clock, value: total[total.length - 1].value + incr}));
        }
        if (each[to].length == 0) {
            each[to].push(Shadow({key: clock, value: incr}));
        } else if (each[to][each[to].length - 1].key != clock) {
            each[to].push(Shadow({key: clock, value: each[to][each[to].length - 1].value + incr}));
        } else {
            each[to][each[to].length - 1].value = each[to][each[to].length - 1].value + incr;
        }
    }

    function burn(uint256 fromActor, Votes decr, uint32 elapsed) public virtual {
        assume(actors.length > 0);
        fromActor = bound(fromActor, 0, actors.length - 1);
        address from = actors[fromActor];
        Votes fromVotes = each[from][each[from].length - 1].value;
        assume(Votes.unwrap(fromVotes) > 0);
        decr = Votes.wrap(bound(Votes.unwrap(decr), 1, Votes.unwrap(fromVotes)));
        assume(elapsed > 1);

        clock += elapsed;
        dut.burn(from, decr, clock);

        assertTrue(isRegistered[from]);
        assertGt(each[from].length, 0);
        assertTrue(from != address(0)); // TODO: could be `assertNotEq`, but would need support in `Boilerplate`

        total.push(Shadow({key: clock, value: total[total.length - 1].value - decr}));
        each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value - decr}));
    }

    function burn(uint256 fromActor, Votes decr) public virtual {
        assume(actors.length > 0);
        fromActor = bound(fromActor, 0, actors.length - 1);
        address from = actors[fromActor];
        Votes fromVotes = each[from][each[from].length - 1].value;
        assume(Votes.unwrap(fromVotes) > 0);
        decr = Votes.wrap(bound(Votes.unwrap(decr), 1, Votes.unwrap(fromVotes)));

        dut.burn(from, decr, clock);

        assertTrue(isRegistered[from]);
        assertGt(each[from].length, 0);
        assertTrue(from != address(0)); // TODO: could be `assertNotEq`, but would need support in `Boilerplate`

        if (total[total.length - 1].key == clock) {
            total[total.length - 1].value = total[total.length - 1].value - decr;
        } else {
            total.push(Shadow({key: clock, value: total[total.length - 1].value - decr}));
        }
        if (each[from][each[from].length - 1].key != clock) {
            each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value - decr}));
        } else {
            each[from][each[from].length - 1].value = each[from][each[from].length - 1].value - decr;
        }
    }

    function transfer(uint256 fromActor, address to, Votes incr, Votes decr, uint32 elapsed) public virtual {
        assume(actors.length > 0);
        fromActor = bound(fromActor, 0, actors.length - 1);
        address from = actors[fromActor];
        assume(to != address(0));
        incr = Votes.wrap(bound(Votes.unwrap(incr), 1, (2 ** 145 - 1) >> 16));
        assume(each[from].length > 0);
        Votes fromVotes = each[from][each[from].length - 1].value;
        assume(Votes.unwrap(fromVotes) > 0);
        decr = Votes.wrap(bound(Votes.unwrap(decr), 1, Votes.unwrap(fromVotes)));
        assume(elapsed > 1);

        clock += elapsed;
        dut.transfer(from, to, incr, decr, clock);

        assertTrue(isRegistered[from]);
        assertGt(each[from].length, 0);
        assertTrue(from != address(0)); // TODO: could be `assertNotEq`, but would need support in `Boilerplate`

        if (!isRegistered[to]) {
            actors.push(to);
            isRegistered[to] = true;
        }

        total.push(Shadow({key: clock, value: total[total.length - 1].value + incr - decr}));
        if (from == to) {
            each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value + incr - decr}));
        } else {
            each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value - decr}));
            if (each[to].length == 0) {
                each[to].push(Shadow({key: clock, value: incr}));
            } else {
                each[to].push(Shadow({key: clock, value: each[to][each[to].length - 1].value + incr}));
            }
        }
    }

    function transfer(uint256 fromActor, address to, Votes incr, Votes decr) public virtual {
        assume(actors.length > 0);
        fromActor = bound(fromActor, 0, actors.length - 1);
        address from = actors[fromActor];
        assume(to != address(0));
        incr = Votes.wrap(bound(Votes.unwrap(incr), 1, (2 ** 145 - 1) >> 16));
        assume(each[from].length > 0);
        Votes fromVotes = each[from][each[from].length - 1].value;
        assume(Votes.unwrap(fromVotes) > 0);
        decr = Votes.wrap(bound(Votes.unwrap(decr), 1, Votes.unwrap(fromVotes)));

        dut.transfer(from, to, incr, decr, clock);

        assertTrue(isRegistered[from]);
        assertGt(each[from].length, 0);
        assertTrue(from != address(0)); // TODO: could be `assertNotEq`, but would need support in `Boilerplate`

        if (!isRegistered[to]) {
            actors.push(to);
            isRegistered[to] = true;
        }

        if (total[total.length - 1].key == clock) {
            total[total.length - 1].value = total[total.length - 1].value + incr - decr;
        } else {
            total.push(Shadow({key: clock, value: total[total.length - 1].value + incr - decr}));
        }
        if (from == to) {
            if (each[from][each[from].length - 1].key != clock) {
                each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value + incr - decr}));
            } else {
                each[from][each[from].length - 1].value = each[from][each[from].length - 1].value + incr - decr;
            }
        } else {
            if (each[from][each[from].length - 1].key != clock) {
                each[from].push(Shadow({key: clock, value: each[from][each[from].length - 1].value - decr}));
            } else {
                each[from][each[from].length - 1].value = each[from][each[from].length - 1].value - decr;
            }

            if (each[to].length == 0) {
                each[to].push(Shadow({key: clock, value: incr}));
            } else if (each[to][each[to].length - 1].key != clock) {
                each[to].push(Shadow({key: clock, value: each[to][each[to].length - 1].value + incr}));
            } else {
                each[to][each[to].length - 1].value = each[to][each[to].length - 1].value + incr;
            }
        }
    }

    function invariant_total() public view virtual {
        if (total.length == 0) {
            return;
        }
        {
            Votes actual = dut.getTotal(total[0].key - 1);
            assertEq(Votes.unwrap(actual), 0);
        }
        for (uint256 i; i < total.length; i++) {
            Shadow storage expected = total[i];
            Votes actual = dut.getTotal(expected.key);
            assertEq(Votes.unwrap(actual), Votes.unwrap(expected.value));
            actual = dut.getTotal(expected.key + 1);
            assertEq(Votes.unwrap(actual), Votes.unwrap(expected.value));
        }
    }

    function invariant_actors() public view virtual {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            {
                Votes actual = dut.get(actor, each[actor][0].key - 1);
                assertEq(Votes.unwrap(actual), 0);
            }
            for (uint256 j; j < each[actor].length; j++) {
                Shadow storage expected = each[actor][j];
                Votes actual = dut.get(actor, expected.key);
                assertEq(Votes.unwrap(actual), Votes.unwrap(expected.value));
                actual = dut.get(actor, expected.key + 1);
                assertEq(Votes.unwrap(actual), Votes.unwrap(expected.value));
            }
        }
    }

    function invariant_totalactors() public view virtual {
        if (total.length == 0) {
            return;
        }
        for (uint256 i; i < actors.length; i++) {
            assertEq(Votes.unwrap(dut.get(actors[i], total[0].key - 1)), 0);
        }
        for (uint256 i; i < total.length; i++) {
            uint48 key = total[i].key;
            Votes expected = total[i].value;
            Votes actual;
            for (uint256 j; j < actors.length; j++) {
                actual = actual + dut.get(actors[j], key);
            }
            assertEq(Votes.unwrap(actual), Votes.unwrap(expected));
        }
    }
}
