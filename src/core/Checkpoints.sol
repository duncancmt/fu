// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC5805} from "../interfaces/IERC5805.sol";

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
    function transfer(Checkpoints storage checkpoints, address from, address to, Votes incr, Votes decr, uint48 clock)
        internal
    {
        if (from == address(0)) {
            if (to == address(0)) {
                return;
            }
            return _mint(checkpoints, to, incr, clock);
        }
        if (to == address(0)) {
            return _burn(checkpoints, from, decr, clock);
        }
        {
            Checkpoint[] storage arr = checkpoints.each[from];
            (Votes oldValue, uint256 len) = _get(arr, clock);
            Votes newValue = oldValue - decr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(from, Votes.unwrap(oldValue), Votes.unwrap(newValue));
        }
        {
            Checkpoint[] storage arr = checkpoints.each[to];
            (Votes oldValue, uint256 len) = _get(arr, clock);
            Votes newValue = oldValue + incr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(to, Votes.unwrap(oldValue), Votes.unwrap(newValue));
        }
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

    function _load(Checkpoint[] storage arr)
        private
        view
        returns (Votes value, uint256 len, uint256 key, bytes32 slotValue)
    {
        assembly ("memory-safe") {
            slotValue := sload(arr.slot)
            len := shr(0xa0, slotValue)
            value := and(0xffffffffffffffffffffffffffff, slotValue)
            key := and(0xffffffffffff, shr(0x70, slotValue))
        }
    }

    function _get(Checkpoint[] storage arr, uint48 clock) private returns (Votes value, uint256 len) {
        uint256 key;
        bytes32 slotValue;
        (value, len, key, slotValue) = _load(arr);
        assembly ("memory-safe") {
            if mul(key, gt(and(0xffffffffffff, clock), key)) {
                mstore(0x00, arr.slot)
                sstore(add(keccak256(0x00, 0x20), len), and(0xffffffffffffffffffffffffffffffffffffffff, slotValue))
                len := add(0x01, len)
            }
        }
    }

    function _set(Checkpoint[] storage arr, uint48 clock, Votes value, uint256 len) private {
        assembly ("memory-safe") {
            sstore(
                arr.slot,
                or(
                    shl(0xa0, len),
                    or(shl(0x70, and(0xffffffffffff, clock)), and(0xffffffffffffffffffffffffffff, value))
                )
            )
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
            Votes newValue = oldValue + incr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(to, Votes.unwrap(oldValue), Votes.unwrap(newValue));
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
            Votes newValue = oldValue - decr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(from, Votes.unwrap(oldValue), Votes.unwrap(newValue));
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

    function _bisect(Checkpoint[] storage arr, uint256 timepoint) private view returns (Votes value) {
        uint256 len;
        {
            uint256 key;
            (value, len, key,) = _load(arr);
            if (key <= timepoint) {
                return value;
            }
        }
        assembly ("memory-safe") {
            mstore(0x00, arr.slot)
            let start := keccak256(0x00, 0x20)
            let hi := add(start, len)
            let lo := start
            let slotValue := sload(lo)
            for {} true {} {
                let key := and(0xffffffffffff, shr(0x70, slotValue))
                if iszero(lt(timepoint, key)) { break }
                let newLo := sub(lo, shl(0x01, sub(hi, lo)))
                hi := lo
                lo := newLo
                if lt(lo, start) {
                    lo := start
                    slotValue := sload(lo)
                    break
                }
                slotValue := sload(lo)
            }
            lo := add(0x01, lo)
            for {} xor(hi, lo) {} {
                let mid := add(shr(0x01, sub(hi, lo)), lo)
                let newSlotValue := sload(mid)
                let key := and(0xffffffffffff, shr(0x70, newSlotValue))
                if lt(timepoint, key) {
                    // down
                    hi := mid
                }
                // up
                slotValue := newSlotValue
                lo := add(0x01, mid)
            }
            if iszero(lt(timepoint, and(0xffffffffffff, shr(0x70, slotValue)))) {
                value := and(0xffffffffffffffffffffffffffff, slotValue)
            }
        }
    }

    function get(Checkpoints storage checkpoints, address account, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.each[account], timepoint);
    }

    function getTotal(Checkpoints storage checkpoints, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.total, timepoint);
    }
}
