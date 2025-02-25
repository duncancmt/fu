// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {Settings} from "./Settings.sol";
import {applyWhaleLimit} from "./WhaleLimit.sol";

import {Tokens, ZERO as ZERO_TOKENS} from "../types/Tokens.sol";
import {Shares, SharesStorage, ONE as ONE_SHARE} from "../types/Shares.sol";
import {SharesToTokens} from "../types/TokensXShares.sol";
import {Tokens} from "../types/Tokens.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";

struct RebaseQueueElem {
    address prev;
    address next;
    Tokens lastTokens;
}

struct RebaseQueue {
    mapping(address => RebaseQueueElem) queue;
    address head;
}

library LibRebaseQueue {
    using UnsafeMath for uint256;
    using SharesToTokens for Shares;

    function initialize(RebaseQueue storage self, address account, Tokens tokens) internal {
        self.head = account;
        RebaseQueueElem storage elem = self.queue[account];
        elem.prev = account;
        elem.next = account;
        elem.lastTokens = tokens;
    }

    function enqueue(RebaseQueue storage self, address account, Tokens balance) internal {
        RebaseQueueElem storage elem = self.queue[account];
        address head = self.head;
        RebaseQueueElem storage headElem = self.queue[head];
        address tail = headElem.prev;

        elem.prev = tail;
        elem.next = head;
        elem.lastTokens = balance;

        self.queue[tail].next = account;
        headElem.prev = account;
    }

    function enqueue(RebaseQueue storage self, address account, Shares shares, Tokens totalSupply, Shares totalShares)
        internal
    {
        return enqueue(self, account, shares.toTokens(totalSupply, totalShares));
    }

    function dequeue(RebaseQueue storage self, address account) internal {
        RebaseQueueElem storage elem = self.queue[account];
        elem.lastTokens = ZERO_TOKENS;
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
        elem.lastTokens = shares.toTokens(totalSupply, totalShares);

        if (self.head == account) {
            self.head = elem.next;
            return;
        }

        address next = elem.next;
        address head = self.head;
        if (next == head) {
            return;
        }
        address prev = elem.prev;
        RebaseQueueElem storage headElem = self.queue[head];
        address tail = headElem.prev;

        elem.prev = tail;
        elem.next = head;

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
    ) private returns (Tokens newTokens) {
        Tokens oldTokens = elem.lastTokens;
        newTokens = shares.toTokens(totalSupply, totalShares);
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
        mapping(address => SharesStorage) storage sharesOf,
        Tokens totalSupply,
        Shares totalShares
    ) internal {
        address cursor = self.head;
        RebaseQueueElem storage elem = self.queue[cursor];
        uint256 i;
        assembly ("memory-safe") {
            mstore(0x00, gas())
            i := shr(0xfd, keccak256(0x00, 0x20))
        }
        for (;; i = i.unsafeDec()) {
            (Shares shares, Shares totalSharesLimited) = applyWhaleLimit(sharesOf[cursor].load(), totalShares);
            elem.lastTokens = _rebaseFor(elem, cursor, shares, totalSupply, totalSharesLimited);
            cursor = elem.next;
            if (i == 0) {
                break;
            }
            elem = self.queue[cursor];
        }
        self.head = cursor;
    }
}
