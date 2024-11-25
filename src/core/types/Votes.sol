// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "../Settings.sol";

import {Shares} from "./Shares.sol";

type Votes is uint208;

function toVotes(Shares s) pure returns (Votes) {
    return Votes.wrap(uint208(Shares.unwrap(s.div(Settings.SHARES_TO_VOTES_DIVISOR))));
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

using {__add as +, __sub as -} for Votes global;
