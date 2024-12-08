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
    // TODO: introduce a new type that represents minted tokens (or balance relative to max address)
    CrazyBalance lastTokens;
}

struct RebaseQueue {
    mapping(address => RebaseQueueElem) queue;
    address head;
}

library LibRebaseQueue {
    using UnsafeMath for uint256;
    using CrazyBalanceArithmetic for Shares;

    function initialize(RebaseQueue storage self, address account, CrazyBalance tokens) internal {
        self.head = account;
        RebaseQueueElem storage elem = self.queue[account];
        elem.prev = account;
        elem.lastTokens = tokens;
    }

    function enqueue(RebaseQueue storage self, address account, Shares shares, Tokens totalSupply, Shares totalShares)
        internal
    {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastTokens = shares.toCrazyBalance(totalSupply, totalShares);
        address tail = self.queue[self.head].prev;
        elem.prev = tail;
        self.queue[tail].next = account;
    }

    function dequeue(RebaseQueue storage self, address account) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastTokens = ZERO_BALANCE;
        self.queue[elem.next].prev = elem.prev;
        if (account == self.head) {
            self.head = elem.next;
        } else {
            self.queue[elem.prev].next = elem.next;
        }
        elem.prev = address(0);
        elem.next = address(0);
    }

    function moveToBack(
        RebaseQueue storage self,
        address account,
        Shares shares,
        Tokens totalSupply,
        Shares totalShares
    ) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastTokens = shares.toCrazyBalance(totalSupply, totalShares);
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
    ) private returns (CrazyBalance newTokens) {
        CrazyBalance oldTokens = elem.lastTokens;
        newTokens = shares.toCrazyBalance(address(type(uint160).max), totalSupply, totalShares);
        if (newTokens > oldTokens) {
            emit IERC20.Transfer(address(0), account, (newTokens - oldTokens).toExternal());
        }
    }

    function rebaseFor(RebaseQueue storage self, address account, Shares shares, Tokens totalSupply, Shares totalShares)
        internal
    {
        _rebaseFor(self.queue[account], account, shares, totalSupply, totalShares);
    }

    function processQueue(
        RebaseQueue storage self,
        mapping(address => Shares) storage sharesOf,
        Tokens totalSupply,
        Shares totalShares
    ) internal {
        address cursor = self.head;
        RebaseQueueElem storage elem = self.queue[cursor];
        self.queue[elem.prev].next = cursor;
        for (uint256 i = gasleft() & 7;; i = i.unsafeDec()) {
            elem.lastTokens = _rebaseFor(elem, cursor, sharesOf[cursor], totalSupply, totalShares);
            if (i == 0) {
                break;
            }
            cursor = elem.next;
            elem = self.queue[cursor];
        }
        elem.next = address(0);
        self.head = cursor;
    }
}
