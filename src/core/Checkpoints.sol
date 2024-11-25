// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Votes} from "./types/Votes.sol";

struct Checkpoint {
    Votes value;
    uint48 key;
}

struct Checkpoints {
    Checkpoint[] total;
    mapping(address => Checkpoint[]) each;
}

library LibCheckpoints {
    function transfer(Checkpoints storage checkpoints, address from, address to, Votes incr, Votes decr, uint48 clock) internal {
        if (from == address(0)) {
            if (to == address(0)) {
                return;
            }
            return _mint(checkpoints, to, incr, clock);
        }
        if (to == address(0)) {
            return _burn(checkpoints, from, decr, clock);
        }
        revert("unimplemented");
    }

    function mint(Checkpoints storage checkpoints, address to, Votes incr, uint48 clock) internal {
        if (to == address(0)) {
            return;
        }
        return _mint(checkpoints, to, incr, clock);
    }

    function burn(Checkpoints storage checkpoints, address from, Votes decr, uint48 clock) internal {
        if (from == address(0)) {
            return;
        }
        return _burn(checkpoints, from, decr, clock);
    }

    function _mint(Checkpoints storage checkpoints, address to, Votes incr, uint48 clock) private {
        revert("unimplemented");
    }
    function _burn(Checkpoints storage checkpoints, address to, Votes decr, uint48 clock) private {
        revert("unimplemented");
    }

    function current(Checkpoints storage checkpoints, address account) internal view returns (Votes) {
        revert("unimplemented");
    }
    function currentTotal(Checkpoints storage checkpoints) internal view returns (Votes) {
        revert("unimplemented");
    }
}
