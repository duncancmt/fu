// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {Settings} from "./Settings.sol";

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
        elem.next = account;
        elem.lastTokens = tokens;
    }

    function enqueue(RebaseQueue storage self, address account, Shares shares, Tokens totalSupply, Shares totalShares)
        internal
    {
        RebaseQueueElem storage elem = self.queue[account];
        address head = self.head;
        RebaseQueueElem storage headElem = self.queue[head];
        address tail = headElem.prev;

        elem.prev = tail;
        elem.next = head;
        elem.lastTokens = shares.toCrazyBalance(totalSupply, totalShares);

        self.queue[tail].next = account;
        headElem.prev = account;
    }

    function dequeue(RebaseQueue storage self, address account) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastTokens = ZERO_BALANCE;
        address prev = elem.prev;
        address next = elem.next;

        elem.prev = address(0);
        elem.next = address(0);

        self.queue[prev].next = next;
        self.queue[next].prev = prev;

        if (self.head == account) {
            self.head = next;
        }
    }

    function moveToBack(
        RebaseQueue storage self,
        address account,
        Shares shares,
        Tokens totalSupply,
        Shares totalShares
    ) internal {
        RebaseQueueElem storage elem = self.queue[account];

        if (self.head == account) {
            self.head = elem.next;
            return;
        }

        address prev = elem.prev;
        address next = elem.next;
        address head = self.head;
        RebaseQueueElem storage headElem = self.queue[head];
        address tail = headElem.prev;

        elem.prev = tail;
        elem.next = head;
        elem.lastTokens = shares.toCrazyBalance(totalSupply, totalShares);

        self.queue[prev].next = next;
        self.queue[next].prev = prev;

        self.queue[tail].next = account;
        headElem.prev = account;
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
        } else {
            newTokens = oldTokens;
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
        for (uint256 i = gasleft() & 7;; i = i.unsafeDec()) {
            Shares shares = sharesOf[cursor];
            if (shares > totalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
                shares = totalShares.div(Settings.ANTI_WHALE_DIVISOR);
            }
            elem.lastTokens = _rebaseFor(elem, cursor, shares, totalSupply, totalShares);
            cursor = elem.next;
            if (i == 0) {
                break;
            }
            elem = self.queue[cursor];
        }
        self.head = cursor;
    }
}
