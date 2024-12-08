// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {CrazyBalance, ZERO as ZERO_BALANCE, CrazyBalanceArithmetic} from "../types/CrazyBalance.sol";
import {Shares} from "../types/Shares.sol";
import {Tokens} from "../types/Tokens.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";

// TODO: this should be a library, not an abstract contract
abstract contract RebaseQueue {
    using UnsafeMath for uint256;
    using CrazyBalanceArithmetic for Shares;

    struct RebaseQueue {
        address prev;
        address next;
        CrazyBalance lastBalance;
    }
    mapping(address => RebaseQueue) internal rebaseQueue;
    address internal rebaseQueueHead;

    function _enqueue(address account, CrazyBalance balance) internal {
        RebaseQueue storage self = rebaseQueue[account];
        self.lastBalance = balance;
        self.prev = rebaseQueue[rebaseQueueHead].prev;
    }

    function _dequeue(address account) internal {
        RebaseQueue storage self = rebaseQueue[account];
        self.lastBalance = ZERO_BALANCE;
        rebaseQueue[self.next].prev = self.prev;
        if (account == rebaseQueueHead) {
            rebaseQueueHead = self.next;
        } else {
            rebaseQueue[self.prev].next = self.next;
        }
        self.prev = address(0);
        self.next = address(0);
    }

    function _moveToBack(address account, CrazyBalance balance) internal {
        RebaseQueue storage self = rebaseQueue[account];
        self.lastBalance = balance;
        address prev;
        if (account == rebaseQueueHead) {
            rebaseQueueHead = self.next;
            prev = self.prev;
        } else {
            rebaseQueue[self.next].prev = self.prev;
            rebaseQueue[self.prev].next = self.next;
            prev = rebaseQueue[rebaseQueueHead].prev;
            self.prev = prev;
        }
        self.next = address(0);
        rebaseQueue[prev].next = account;
    }

    function _rebaseFor(address account, Shares shares, Tokens totalSupply, Shares totalShares) internal returns (CrazyBalance newBalance) {
        /*
        if (account == address(pair)) {
            return;
        }
        */
        CrazyBalance oldBalance = rebaseQueue[account].lastBalance;
        newBalance = shares.toCrazyBalance(account, totalSupply, totalShares);
        if (oldBalance != newBalance) {
            emit IERC20.Transfer(address(0), account, (newBalance - oldBalance).toExternal());
        }
    }

    function _processQueue(mapping(address => Shares) storage sharesOf, Tokens totalSupply, Shares totalShares) internal {
        address cursor = rebaseQueueHead;
        for (uint256 i = gasleft() & 7; ; i = i.unsafeDec()) {
            RebaseQueue storage self = rebaseQueue[cursor];

            CrazyBalance oldBalance = self.lastBalance;
            CrazyBalance newBalance = sharesOf[cursor].toCrazyBalance(cursor, totalSupply, totalShares);
            if (oldBalance != newBalance) {
                emit IERC20.Transfer(address(0), cursor, (newBalance - oldBalance).toExternal());
            }
            self.lastBalance = newBalance;
            if (i == 0) {
                break;
            }
            cursor = self.next;
        }
        rebaseQueueHead = cursor;
        // TODO: fixup `rebaseQueue[rebaseQueue[rebaseQueueHead].prev].next` and `rebaseQueue[cursor].next`
    }
}
