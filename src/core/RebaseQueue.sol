// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {CrazyBalance, ZERO as ZERO_BALANCE, CrazyBalanceArithmetic} from "../types/CrazyBalance.sol";
import {Shares} from "../types/Shares.sol";
import {Tokens} from "../types/Tokens.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";

struct RebaseQueueElem {
    address prev;
    address next;
    CrazyBalance lastBalance;
}

struct RebaseQueue {
    mapping(address => RebaseQueueElem) queue;
    address head;
}

library LibRebaseQueue {
    using UnsafeMath for uint256;
    using CrazyBalanceArithmetic for Shares;

    function enqueue(RebaseQueue storage self, address account, CrazyBalance balance) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastBalance = balance;
        elem.prev = self.queue[self.head].prev;
    }

    function dequeue(RebaseQueue storage self, address account) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastBalance = ZERO_BALANCE;
        self.queue[elem.next].prev = elem.prev;
        if (account == self.head) {
            self.head = elem.next;
        } else {
            self.queue[elem.prev].next = elem.next;
        }
        elem.prev = address(0);
        elem.next = address(0);
    }

    function moveToBack(RebaseQueue storage self, address account, CrazyBalance balance) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastBalance = balance;
        address prev;
        if (account == self.head) {
            self.head = elem.next;
            prev = elem.prev;
        } else {
            self.queue[elem.next].prev = elem.prev;
            self.queue[elem.prev].next = elem.next;
            prev = self.queue[self.head].prev;
            elem.prev = prev;
        }
        elem.next = address(0);
        self.queue[prev].next = account;
    }

    function _rebaseFor(
        RebaseQueueElem storage elem,
        address account,
        Shares shares,
        Tokens totalSupply,
        Shares totalShares
    ) internal returns (CrazyBalance newBalance) {
        CrazyBalance oldBalance = elem.lastBalance;
        newBalance = shares.toCrazyBalance(account, totalSupply, totalShares);
        if (oldBalance != newBalance) {
            emit IERC20.Transfer(address(0), account, Tokens.unwrap((newBalance - oldBalance).toTokens(account)));
        }
    }

    function rebaseFor(RebaseQueue storage self, address account, Shares shares, Tokens totalSupply, Shares totalShares)
        private
        returns (CrazyBalance)
    {
        return _rebaseFor(self.queue[account], account, shares, totalSupply, totalShares);
    }

    function processQueue(
        RebaseQueue storage self,
        mapping(address => Shares) storage sharesOf,
        Tokens totalSupply,
        Shares totalShares
    ) internal {
        address cursor = self.head;
        for (uint256 i = gasleft() & 7;; i = i.unsafeDec()) {
            RebaseQueueElem storage elem = self.queue[cursor];

            elem.lastBalance = _rebaseFor(elem, cursor, sharesOf[cursor], totalSupply, totalShares);
            if (i == 0) {
                break;
            }
            cursor = elem.next;
        }
        self.head = cursor;
        // TODO: fixup `self.queue[self.queue[self.head].prev].next` and `self.queue[cursor].next`
    }
}
