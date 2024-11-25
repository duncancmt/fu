// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Votes} from "./types/Votes.sol";

struct Checkpoint {
    uint96 _pad;
    uint48 key;
    Votes value;
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

    function _get(Checkpoint[] storage arr, uint48 clock) private returns (Votes value, uint256 len) {
        assembly ("memory-safe") {
            let slotValue := sload(arr.slot)
            len := shr(0xa0, slotValue)
            value := and(0xffffffffffffffffffffffffffff, slotValue)
            let key := and(0xffffffffffff, shr(0x70, slotValue))
            if mul(key, gt(and(0xffffffffffff, clock), key)) {
                mstore(0x00, arr.slot)
                sstore(add(keccak256(0x00, 0x20), len), and(0xffffffffffffffffffffffffffffffffffffffff, slotValue))
                len := add(0x01, len)
            }
        }
    }

    function _set(Checkpoint[] storage arr, uint48 clock, Votes value, uint256 len) private {
        assembly ("memory-safe") {
            sstore(arr.slot, or(shl(0xa0, len), or(shl(0x70, and(0xffffffffffff, clock)), and(0xffffffffffffffffffffffffffff, value))))
        }
    }

    function _mint(Checkpoints storage checkpoints, address to, Votes incr, uint48 clock) private {
        {
            Checkpoint[] storage arr = checkpoints.total;
            (Votes oldValue, uint256 len) = _get(arr, clock);
            _set(arr, clock, oldValue + incr, len);
        }
        {
            Checkpoint[] storage arr = checkpoints.each[to];
            (Votes oldValue, uint256 len) = _get(checkpoints.each[to], clock);
            _set(arr, clock, oldValue + incr, len);
        }
    }

    function _burn(Checkpoints storage checkpoints, address from, Votes decr, uint48 clock) private {
        {
            Checkpoint[] storage arr = checkpoints.total;
            (Votes oldValue, uint256 len) = _get(arr, clock);
            _set(arr, clock, oldValue - decr, len);
        }
        {
            Checkpoint[] storage arr = checkpoints.each[from];
            (Votes oldValue, uint256 len) = _get(checkpoints.each[from], clock);
            _set(arr, clock, oldValue - decr, len);
        }
    }

    function current(Checkpoints storage checkpoints, address account) internal view returns (Votes value) {
        Checkpoint[] storage each = checkpoints.each[account];
        assembly ("memory-safe") {
            value := sload(each.slot)
        }
    }
    function currentTotal(Checkpoints storage checkpoints) internal view returns (Votes value) {
        Checkpoint[] storage total = checkpoints.total;
        assembly ("memory-safe") {
            value := sload(total.slot)
        }
    }
}
