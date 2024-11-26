// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC5805} from "../interfaces/IERC5805.sol";

import {Votes} from "./types/Votes.sol";

struct Checkpoint {
    uint48 key;
    uint96 _pad;
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
        if (from == to) {
            if (incr > decr) {
                _mint(checkpoints, from, incr - decr, clock);
            }
            if (incr < decr) {
                _burn(checkpoints, to, decr - incr, clock);
            }
            return;
        }
        if (incr > decr) {
            _mint(checkpoints, incr - decr, clock);
        }
        if (incr < decr) {
            _burn(checkpoints, decr - incr, clock);
        }
        {
            Checkpoint[] storage arr = checkpoints.each[from];
            (Votes oldValue, uint256 len) = _get(arr, clock);
            Votes newValue = oldValue - decr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(from, oldValue.toExternal(), newValue.toExternal());
        }
        {
            Checkpoint[] storage arr = checkpoints.each[to];
            (Votes oldValue, uint256 len) = _get(arr, clock);
            Votes newValue = oldValue + incr;
            _set(arr, clock, newValue, len);
            emit IERC5805.DelegateVotesChanged(to, oldValue.toExternal(), newValue.toExternal());
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
            key := shr(0xd0, slotValue)
            len := and(0xffffffffffffffffffffffff, shr(0x70, slotValue))
            value := and(0xffffffffffffffffffffffffffff, slotValue)
        }
    }

    function _get(Checkpoint[] storage arr, uint48 clock) private returns (Votes value, uint256 len) {
        uint256 key;
        bytes32 slotValue;
        (value, len, key, slotValue) = _load(arr);
        assembly ("memory-safe") {
            if mul(key, gt(and(0xffffffffffff, clock), key)) {
                mstore(0x00, arr.slot)
                sstore(
                    add(keccak256(0x00, 0x20), len),
                    and(0xffffffffffff000000000000000000000000ffffffffffffffffffffffffffff, slotValue)
                )
                len := add(0x01, len)
            }
        }
    }

    function _set(Checkpoint[] storage arr, uint48 clock, Votes value, uint256 len) private {
        assembly ("memory-safe") {
            sstore(arr.slot, or(shl(0x70, len), or(shl(0xd0, clock), and(0xffffffffffffffffffffffffffff, value))))
        }
    }

    function _mint(Checkpoints storage checkpoints, Votes incr, uint48 clock) private {
        Checkpoint[] storage arr = checkpoints.total;
        (Votes oldValue, uint256 len) = _get(arr, clock);
        _set(arr, clock, oldValue + incr, len);
    }

    function _mint(Checkpoints storage checkpoints, address to, Votes incr, uint48 clock) private {
        _mint(checkpoints, incr, clock);
        Checkpoint[] storage arr = checkpoints.each[to];
        (Votes oldValue, uint256 len) = _get(arr, clock);
        Votes newValue = oldValue + incr;
        _set(arr, clock, newValue, len);
        emit IERC5805.DelegateVotesChanged(to, oldValue.toExternal(), newValue.toExternal());
    }

    function _burn(Checkpoints storage checkpoints, Votes decr, uint48 clock) private {
        Checkpoint[] storage arr = checkpoints.total;
        (Votes oldValue, uint256 len) = _get(arr, clock);
        _set(arr, clock, oldValue - decr, len);
    }

    function _burn(Checkpoints storage checkpoints, address from, Votes decr, uint48 clock) private {
        _burn(checkpoints, decr, clock);
        Checkpoint[] storage arr = checkpoints.each[from];
        (Votes oldValue, uint256 len) = _get(arr, clock);
        Votes newValue = oldValue - decr;
        _set(arr, clock, newValue, len);
        emit IERC5805.DelegateVotesChanged(from, oldValue.toExternal(), newValue.toExternal());
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

    function _bisect(Checkpoint[] storage arr, uint256 query) private view returns (Votes value) {
        uint256 len;
        {
            uint256 key;
            (value, len, key,) = _load(arr);
            if (key <= query) {
                return value;
            }
        }
        assembly ("memory-safe") {
            // A dynamic array's elements are encoded in storage beginning at
            // the slot named by the hash of the base slot
            mstore(0x00, arr.slot)
            let start := keccak256(0x00, 0x20)

            // Because we tend to query near the current time, we optimize by
            // bounding our search to progressively larger portions near the end
            // of the array, until we find one that contains the checkpoint of
            // interest
            let hi := add(start, len)
            let lo := sub(hi, 0x01)
            for {} true {} {
                value := sload(lo)
                if iszero(gt(shr(0xd0, value), query)) { break }
                let newLo := sub(lo, shl(0x01, sub(hi, lo)))
                hi := lo
                lo := newLo
                if lt(lo, start) {
                    lo := start
                    value := sload(lo)
                    break
                }
            }

            // Apply normal binary search
            lo := add(0x01, lo)
            for {} xor(hi, lo) {} {
                let mid := add(shr(0x01, sub(hi, lo)), lo)
                let newValue := sload(mid)
                if gt(shr(0xd0, newValue), query) {
                    // down
                    hi := mid
                    continue
                }
                // up
                value := newValue
                lo := add(0x01, mid)
            }

            // Because we do not snapshot the initial, empty checkpoint, we have
            // to detect that we've run off the front of the array and zero-out
            // the return value
            if gt(shr(0xd0, value), query) { value := 0 }
        }
    }

    function get(Checkpoints storage checkpoints, address account, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.each[account], timepoint);
    }

    function getTotal(Checkpoints storage checkpoints, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.total, timepoint);
    }
}
