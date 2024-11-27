// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "../Settings.sol";

import {Shares} from "./Shares.sol";

type Votes is uint144;

function toVotes(Shares s) pure returns (Votes) {
    return Votes.wrap(uint144(Shares.unwrap(s.div(Settings.SHARES_TO_VOTES_DIVISOR))));
}

function toExternal(Votes v) pure returns (uint256) {
    return Votes.unwrap(v);
}

using {toExternal} for Votes global;

function __add(Votes a, Votes b) pure returns (Votes) {
    unchecked {
        return Votes.wrap(Votes.unwrap(a) + Votes.unwrap(b));
    }
}

function __sub(Votes a, Votes b) pure returns (Votes) {
    unchecked {
        return Votes.wrap(Votes.unwrap(a) - Votes.unwrap(b));
    }
}

function __eq(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) == Votes.unwrap(b);
}

function __lt(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) < Votes.unwrap(b);
}

function __gt(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) > Votes.unwrap(b);
}

function __ne(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) != Votes.unwrap(b);
}

function __le(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) <= Votes.unwrap(b);
}

function __ge(Votes a, Votes b) pure returns (bool) {
    return Votes.unwrap(a) >= Votes.unwrap(b);
}

using {
    __add as +, __sub as -, __eq as ==, __lt as <, __gt as >, __ne as !=, __le as <=, __ge as >=
} for Votes global;
