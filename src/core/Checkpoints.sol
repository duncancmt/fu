// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Votes} from "./types/Votes.sol";

struct Checkpoint {
    Votes value;
    uint48 key;
}

library LibCheckpoints {
    function add(mapping(address => Checkpoint[]) storage checkpoints, address delegate, Votes delta, uint48 clock) internal {
        if (delegate == address(0)) {
            return;
        }
        revert("unimplemented");
    }
    function sub(mapping(address => Checkpoint[]) storage checkpoints, address delegate, Votes delta, uint48 clock) internal {
        if (delegate == address(0)) {
            return;
        }
        revert("unimplemented");
    }
}
