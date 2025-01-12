// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC5805} from "../interfaces/IERC5805.sol";

import {Settings} from "./Settings.sol";

import {Votes} from "../types/Votes.sol";

struct Checkpoint {
    uint48 key;
    uint56 _pad;
    uint152 value;
}

struct Checkpoints {
    mapping(address => Checkpoint[]) each;
    Checkpoint[] total;
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

    function burn(Checkpoints storage checkpoints, address from0, Votes decr0, address from1, Votes decr1, uint48 clock)
        internal
    {
        if (from0 == address(0)) {
            return burn(checkpoints, from1, decr1, clock);
        }
        if (from1 == address(0)) {
            return _burn(checkpoints, from0, decr0, clock);
        }
        return _burn(checkpoints, from0, decr0, from1, decr1, clock);
    }

    function _load(Checkpoint[] storage arr)
        private
        view
        returns (Votes value, uint256 len, uint256 key, bytes32 slotValue)
    {
        assembly ("memory-safe") {
            slotValue := sload(arr.slot)
            key := shr(0xd0, slotValue)
            len := and(0xffffffffffffff, shr(0x98, slotValue))
            value := and(0x1ffffffffffffffffffffffffffffffffffff, slotValue)
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
                    and(0xffffffffffff0000000000000001ffffffffffffffffffffffffffffffffffff, slotValue)
                )
                len := add(0x01, len)
            }
        }
    }

    function _set(Checkpoint[] storage arr, uint48 clock, Votes value, uint256 len) private {
        assembly ("memory-safe") {
            sstore(
                arr.slot,
                or(
                    shl(0x98, len),
                    or(shl(0xd0, and(0xffffffffffff, clock)), and(0x1ffffffffffffffffffffffffffffffffffff, value))
                )
            )
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

    function _burn(
        Checkpoints storage checkpoints,
        address from0,
        Votes decr0,
        address from1,
        Votes decr1,
        uint48 clock
    ) private {
        _burn(checkpoints, decr0 + decr1, clock);

        Checkpoint[] storage arr = checkpoints.each[from0];
        (Votes oldValue, uint256 len) = _get(arr, clock);
        Votes newValue = oldValue - decr0;
        _set(arr, clock, newValue, len);
        emit IERC5805.DelegateVotesChanged(from0, oldValue.toExternal(), newValue.toExternal());

        arr = checkpoints.each[from1];
        (oldValue, len) = _get(arr, clock);
        newValue = oldValue - decr1;
        _set(arr, clock, newValue, len);
        emit IERC5805.DelegateVotesChanged(from1, oldValue.toExternal(), newValue.toExternal());
    }

    function current(Checkpoints storage checkpoints, address account) internal view returns (Votes value) {
        Checkpoint[] storage each = checkpoints.each[account];
        assembly ("memory-safe") {
            value := and(0x1ffffffffffffffffffffffffffffffffffff, sload(each.slot))
        }
    }

    function currentTotal(Checkpoints storage checkpoints) internal view returns (Votes value) {
        Checkpoint[] storage total = checkpoints.total;
        assembly ("memory-safe") {
            value := and(0x1ffffffffffffffffffffffffffffffffffff, sload(total.slot))
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
        uint256 initialWindow = Settings.BISECT_WINDOW_DEFAULT;
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
            let lo := sub(hi, initialWindow)
            for {} true {} {
                if lt(lo, start) {
                    lo := start
                    value := 0x00
                    break
                }
                value := sload(lo)
                if iszero(gt(shr(0xd0, value), query)) {
                    lo := add(0x01, lo)
                    break
                }
                let newLo := sub(lo, shl(0x01, sub(hi, lo)))
                hi := lo
                lo := newLo
            }

            // Apply normal binary search
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

            value := and(0x1ffffffffffffffffffffffffffffffffffff, value)
        }
    }

    function get(Checkpoints storage checkpoints, address account, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.each[account], timepoint);
    }

    function getTotal(Checkpoints storage checkpoints, uint48 timepoint) internal view returns (Votes) {
        return _bisect(checkpoints.total, timepoint);
    }
}
