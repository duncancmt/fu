// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {IERC5805} from "src/interfaces/IERC5805.sol";
import {FU} from "src/FU.sol";
import {Buyback} from "src/Buyback.sol";
import {Settings} from "src/core/Settings.sol";
import {applyWhaleLimit} from "src/core/WhaleLimit.sol";
import {Shares} from "src/types/Shares.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory, pairFor} from "src/interfaces/IUniswapV2Factory.sol";
import {ChecksumAddress} from "src/lib/ChecksumAddress.sol";
import {UnsafeMath} from "src/lib/UnsafeMath.sol";
import {uint512, alloc, tmp} from "src/lib/512Math.sol";
import {ItoA} from "src/lib/ItoA.sol";

import {FUDeploy, Common} from "./Deploy.t.sol";

import {StdInvariant} from "@forge-std/StdInvariant.sol";
import {VmSafe, Vm} from "@forge-std/Vm.sol";

import {console} from "@forge-std/console.sol";

// Copied directly from Foundry
abstract contract Bound {
    using ItoA for int256;

    function bound(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256 result) {
        require(min <= max, "StdUtils bound(uint256,uint256,uint256): Max is less than min.");
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x >= min && x <= max) return x;

        uint256 size = max - min + 1;

        // If the value is 0, 1, 2, 3, wrap that to min, min+1, min+2, min+3. Similarly for the UINT256_MAX side.
        // This helps ensure coverage of the min/max values.
        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) return max - (type(uint256).max - x);

        // Otherwise, wrap x into the range [min, max], i.e. the range is inclusive.
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }

    function bound(uint256 x, uint256 min, uint256 max, string memory name)
        internal
        pure
        virtual
        returns (uint256 result)
    {
        result = bound(x, min, max);
        console.log(name, result);
    }

    function bound(int256 x, int256 min, int256 max) internal pure virtual returns (int256 result) {
        require(min <= max, "StdUtils bound(int256,int256,int256): Max is less than min.");

        // Shifting all int256 values to uint256 to use _bound function. The range of two types are:
        // int256 : -(2**255) ~ (2**255 - 1)
        // uint256:     0     ~ (2**256 - 1)
        // So, add 2**255, INT256_MIN_ABS to the integer values.
        //
        // If the given integer value is -2**255, we cannot use `-uint256(-x)` because of the overflow.
        // So, use `~uint256(x) + 1` instead.
        uint256 _x = x < 0 ? (uint256(type(int256).min) - ~uint256(x) - 1) : (uint256(x) + uint256(type(int256).min));
        uint256 _min =
            min < 0 ? (uint256(type(int256).min) - ~uint256(min) - 1) : (uint256(min) + uint256(type(int256).min));
        uint256 _max =
            max < 0 ? (uint256(type(int256).min) - ~uint256(max) - 1) : (uint256(max) + uint256(type(int256).min));

        uint256 y = bound(_x, _min, _max);

        // To move it back to int256 value, subtract INT256_MIN_ABS at here.
        result = y < uint256(type(int256).min)
            ? int256(~(uint256(type(int256).min) - y) + 1)
            : int256(y - uint256(type(int256).min));
    }

    function bound(int256 x, int256 min, int256 max, string memory name)
        internal
        pure
        virtual
        returns (int256 result)
    {
        result = bound(x, min, max);
        console.log(name, result.itoa());
    }
}

function saturatingAdd(uint256 x, uint256 y) pure returns (uint256 r) {
    assembly ("memory-safe") {
        r := add(x, y)
        r := or(r, sub(0x00, lt(r, y)))
    }
}

function applyWhaleLimit(uint256 shares0, uint256 shares1, uint256 totalShares)
    pure
    returns (uint256, uint256, uint256)
{
    (Shares shares0_, Shares shares1_, Shares totalShares_) =
        applyWhaleLimit(Shares.wrap(shares0), Shares.wrap(shares1), Shares.wrap(totalShares));
    return (Shares.unwrap(shares0_), Shares.unwrap(shares1_), Shares.unwrap(totalShares_));
}

interface ListOfInvariants {
    function invariant_nonNegativeRebase() external;
    function invariant_delegatesNotChanged() external;
    function invariant_sumOfShares() external;
    function invariant_votingDelegation() external;
    function invariant_delegateeZero() external;
    function invariant_rebaseQueueContents() external;
}

contract FUGuide is Common, Bound, ListOfInvariants {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code"))))); // TODO: remove

    using ItoA for uint256;
    using ChecksumAddress for address;
    using UnsafeMath for uint256;

    mapping(address => uint256) internal lastBalance;
    mapping(address => address) internal shadowDelegates;
    uint32 internal shareRatio = 1;

    constructor(IFU fu_, Buyback buyback_, address[] memory actors_) {
        fu = fu_;
        buyback = buyback_;
        pair = fu.pair();
        setUpActors(actors_);

        lastBalance[DEAD] = fu.balanceOf(DEAD);

        actors.push(pair);
        isActor[pair] = true;

        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            lastBalance[actor] = fu.balanceOf(actor);
        }
    }

    function _sharesSlot(address account) internal pure returns (bytes32 r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, account))
            mstore(0x20, add(BASE_SLOT, 7))
            r := keccak256(0x00, 0x40)
        }
    }

    function _rebaseQueuePrevSlot(address account) internal pure returns (bytes32 r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, account))
            mstore(0x20, add(0x03, BASE_SLOT))
            r := keccak256(0x00, 0x40)
        }
    }

    function _rebaseQueueNextSlot(address account) internal pure returns (bytes32 r) {
        unchecked {
            return bytes32(uint256(_rebaseQueuePrevSlot(account)) + 1);
        }
    }

    function _rebaseQueueLastTokensSlot(address account) internal pure returns (bytes32 r) {
        unchecked {
            return bytes32(uint256(_rebaseQueuePrevSlot(account)) + 2);
        }
    }

    function getShares(address account) internal view returns (uint256) {
        uint256 value = uint256(load(address(fu), _sharesSlot(account)));
        assertEq(
            value & 0xffffffffff00000000000000000000000000000000000000000000ffffffffff,
            0,
            string.concat("dirty shares slot: ", value.itoa())
        );
        return value >> 40;
    }

    function setShares(address account, uint256 newShares) internal {
        return store(address(fu), _sharesSlot(account), bytes32(newShares << 40));
    }

    function getTotalShares() internal view returns (uint256) {
        uint256 value = uint256(load(address(fu), bytes32(uint256(BASE_SLOT) + 2)));
        assertEq(value >> 177, 0, string.concat("dirty total supply slot: ", value.itoa()));
        assertNotEq(value, 0, "zero total shares");
        return value;
    }

    function setTotalShares(uint256 newTotalShares) internal {
        assertNotEq(newTotalShares, 0, "cannot set zero total shares");
        return store(address(fu), bytes32(uint256(BASE_SLOT) + 2), bytes32(newTotalShares));
    }

    function getCirculatingTokens() internal view returns (uint256) {
        uint256 value = uint256(load(address(fu), BASE_SLOT));
        assertEq(value >> 145, 0, string.concat("dirty circulating tokens slot: ", value.itoa()));
        assertNotEq(value, 0, "zero circulating tokens");
        return value;
    }

    function getRebaseQueueHead() internal view returns (address) {
        uint256 slotValue = uint256(load(address(fu), bytes32(uint256(BASE_SLOT) + 4)));
        assertLe(slotValue, type(uint160).max, "dirty rebase queue head slot");
        return address(uint160(slotValue));
    }

    function getRebaseQueuePrev(address account) internal view returns (address) {
        uint256 slotValue = uint256(load(address(fu), _rebaseQueuePrevSlot(account)));
        assertLe(slotValue, type(uint160).max, "dirty rebase queue prev slot");
        return address(uint160(slotValue));
    }

    function getRebaseQueueNext(address account) internal view returns (address) {
        uint256 slotValue = uint256(load(address(fu), _rebaseQueueNextSlot(account)));
        assertLe(slotValue, type(uint160).max, "dirty rebase queue next slot");
        return address(uint160(slotValue));
    }

    function updateRebaseQueueLastTokens(address account, uint256 circulatingTokens, uint256 totalShares) internal {
        uint256 shares = getShares(account);
        uint256 tokens = tmp().omul(shares, circulatingTokens).div(totalShares);
        return store(address(fu), _rebaseQueueLastTokensSlot(account), bytes32(tokens));
    }

    function getActor(uint256 actorIndex) internal override returns (address actor, uint256 originalBalance) {
        (actor,) = super.getActor(actorIndex);
        originalBalance = lastBalance[actor];
        lastBalance[actor] = fu.balanceOf(actor);
    }

    function maybeCreateActor(address newActor) internal override returns (uint256 originalBalance) {
        originalBalance = lastBalance[newActor];
        if (isActor[newActor]) {
            lastBalance[newActor] = fu.balanceOf(newActor);
        }
        super.maybeCreateActor(newActor);
    }

    function saveActor(address actor) internal override {
        super.saveActor(actor);
        lastBalance[actor] = fu.balanceOf(actor);
    }

    function restoreActor(address actor, uint256 originalBalance) internal {
        lastBalance[actor] = originalBalance;
    }

    function updateLastBalanceForRebaseQueue(VmSafe.Log[] memory logs, address skip0, address skip1) internal {
        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (log.topics[0] == IERC20.Transfer.selector && log.topics[1] == bytes32(0)) {
                address acct = address(uint160(uint256(log.topics[2])));
                if (acct == skip0 || acct == skip1) {
                    continue;
                }
                lastBalance[acct] = fu.balanceOf(acct);
            }
        }
    }

    function updateLastBalanceForRebaseQueue(VmSafe.Log[] memory logs, address skip) internal {
        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (log.topics[0] == IERC20.Transfer.selector && log.topics[1] == bytes32(0)) {
                address acct = address(uint160(uint256(log.topics[2])));
                if (acct == skip) {
                    continue;
                }
                lastBalance[acct] = fu.balanceOf(acct);
            }
        }
    }

    function addActor(address newActor) external {
        assume(newActor != address(0));
        assume(newActor != DEAD);
        assume(newActor != address(fu));
        assume(!isActor[newActor]);
        maybeCreateActor(newActor);
        saveActor(newActor);
    }

    function warp(uint24 incr) external {
        incr = uint24(bound(incr, 4 hours, 2 ** 23 - 1));
        warp(getBlockTimestamp() + incr);
    }

    function setSharesRatio(uint32 newRatio) external {
        uint32 oldRatio = shareRatio;
        uint256 fudge = 2; // TODO: decrease
        newRatio = uint32(
            bound(
                newRatio,
                oldRatio,
                Settings.INITIAL_SHARES_RATIO / (Settings.MIN_SHARES_RATIO * fudge),
                "shares divisor"
            )
        );
        assume(newRatio != oldRatio);

        uint256 total;
        {
            uint256 shares = getShares(DEAD) * oldRatio / newRatio;
            total = shares;
            setShares(DEAD, shares);
        }
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];

            if (actor == pair) {
                continue;
            }

            address delegatee = shadowDelegates[actor];
            if (delegatee != address(0)) {
                prank(actor);
                fu.delegate(address(0));
            }

            uint256 oldShares = getShares(actor);
            uint256 newShares = oldShares * oldRatio / newRatio;
            if (oldShares != 0 && newShares == 0) {
                // zeroing the shares of an account that previously had nonzero shares corrupts the rebase queue
                total += oldShares;
            } else {
                total += newShares;
                setShares(actor, newShares);
            }

            if (delegatee != address(0)) {
                prank(actor);
                fu.delegate(delegatee);
            }
        }
        setTotalShares(total);

        // Make the rebase queue consistent
        {
            uint256 circulating = getCirculatingTokens();
            for (uint256 i; i < actors.length; i++) {
                address actor = actors[i];
                if (actor == pair) {
                    continue;
                }
                updateRebaseQueueLastTokens(actors[i], circulating, total);
            }
            updateRebaseQueueLastTokens(DEAD, circulating, total);
        }
        // Update the shadow of the rebase queue
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            lastBalance[actor] = fu.balanceOf(actor);
        }
        lastBalance[DEAD] = fu.balanceOf(DEAD);

        shareRatio = newRatio;
    }

    function _transferShouldFail(address from, address to, uint256 amount, uint256 balance)
        internal
        view
        returns (bool)
    {
        return from == DEAD || to == DEAD || to == address(fu) || to == from || amount > balance
            || uint160(to) / Settings.ADDRESS_DIVISOR == 0;
    }

    function transfer(uint256 actorIndex, address to, uint256 amount, bool boundTo, bool boundAmount) external {
        (address actor, uint256 originalBalance) = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
        } else {
            console.log("amount", amount);
        }
        if (actor == pair) {
            assume(amount < fu.balanceOf(actor));
        }
        uint256 originalBalanceTo;
        if (boundTo) {
            (to, originalBalanceTo) = getActor(to);
        } else {
            originalBalanceTo = maybeCreateActor(to);
        }

        uint256 beforeBalance = lastBalance[actor];
        uint256 beforeBalanceTo = lastBalance[to];
        uint256 beforeWhaleLimit = fu.whaleLimit(actor);
        uint256 beforeWhaleLimitTo = fu.whaleLimit(to);
        bool actorIsWhale = beforeBalance == beforeWhaleLimit;
        bool toIsWhaleBefore = beforeBalanceTo == beforeWhaleLimitTo;
        uint256 beforeShares = getShares(actor);
        uint256 beforeSharesTo = getShares(to);
        uint256 beforeCirculating = getCirculatingTokens();
        uint256 beforeTotalShares = getTotalShares();
        uint256 tax = fu.tax();
        address rebaseQueueHead = getRebaseQueueHead();

        if (!_transferShouldFail(actor, to, amount, beforeBalance)) {
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(actor, to, type(uint256).max);
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(actor, address(0), type(uint256).max);
            uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
            uint256 votes = divisor == 0
                ? 0
                : tmp().omul(amount * Settings.CRAZY_BALANCE_BASIS, beforeTotalShares).div(
                    beforeCirculating * divisor * Settings.SHARES_TO_VOTES_DIVISOR
                );
            address actorDelegatee = fu.delegates(actor);
            address toDelegatee = fu.delegates(actor);
            console.log("votes", votes);
            if (votes != 0 && actorDelegatee != toDelegatee) {
                if (actorDelegatee != address(0)) {
                    expectEmit(true, true, true, false, address(fu));
                    emit IERC5805.DelegateVotesChanged(actorDelegatee, type(uint256).max, type(uint256).max);
                }
                if (toDelegatee != address(0)) {
                    expectEmit(true, true, true, false, address(fu));
                    emit IERC5805.DelegateVotesChanged(toDelegatee, type(uint256).max, type(uint256).max);
                }
            }
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.transfer, (to, amount)));
        assertEq(success, !_transferShouldFail(actor, to, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            restoreActor(actor, originalBalance);
            if (actor != to) {
                restoreActor(to, originalBalanceTo);
            }
            return;
        }

        saveActor(actor);
        saveActor(to);

        uint256 logAmountTransfer;
        uint256 logAmountBurn;
        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (
                log.topics.length == 3 && log.topics[0] == IERC20.Transfer.selector
                    && log.topics[1] == bytes32(uint256(uint160(actor))) && log.topics[2] == bytes32(uint256(uint160(to)))
            ) {
                assertEq(log.emitter, address(fu), "wrong log emitter");
                assertEq(log.data.length, 32, "wrong Transfer data length (amount)");
                logAmountTransfer = uint256(bytes32(log.data));
                log = logs[i + 1];
                assertEq(log.topics.length, 3, "wrong burn Transfer event topics");
                assertEq(log.topics[0], IERC20.Transfer.selector, "wrong burn Transfer event topic0");
                assertEq(log.topics[1], bytes32(uint256(uint160(actor))), "wrong burn Transfer event `from`");
                assertEq(log.topics[2], bytes32(0), "wrong burn Transfer event `to` (zero)");
                assertEq(log.emitter, address(fu), "wrong log emitter");
                assertEq(log.data.length, 32, "wrong burn Transfer data length (amount)");
                logAmountBurn = uint256(bytes32(log.data));

                // delete both the entries we just looked at from `logs`
                assembly ("memory-safe") {
                    let length := sub(mload(logs), 0x02)
                    let start := add(0x20, add(shl(0x05, i), logs))
                    mcopy(start, add(0x40, start), shl(0x05, sub(length, i)))
                    mstore(logs, length)
                }
                break;
            }
        }

        uint256 afterBalance = lastBalance[actor];
        uint256 afterBalanceTo = lastBalance[to];
        uint256 afterWhaleLimit = fu.whaleLimit(actor);
        uint256 afterWhaleLimitTo = fu.whaleLimit(to);
        bool toIsWhale = afterBalanceTo == afterWhaleLimitTo;
        uint256 afterShares = getShares(actor);
        uint256 afterSharesTo = getShares(to);
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterTotalShares = getTotalShares();

        /*
        console.log(
            string.concat(
                "summary"
                "\n\tamount:                ", amount.itoa(),
                "\n\toriginal from balance: ", originalBalance.itoa(),
                "\n\tbefore from balance:   ", beforeBalance.itoa(),
                "\n\tafter from balance:    ", afterBalance.itoa(),
                "\n\tbefore whale limit:    ", beforeWhaleLimit.itoa(),
                "\n\tafter whale limit:     ", afterWhaleLimit.itoa(),
                "\n\toriginal to balance:   ", originalBalanceTo.itoa(),
                "\n\tbefore to balance:     ", beforeBalanceTo.itoa(),
                "\n\tafter to balance:      ", afterBalanceTo.itoa(),
                "\n\tbefore whale limit to: ", beforeWhaleLimitTo.itoa(),
                "\n\tafter whale limit to:  ", afterWhaleLimitTo.itoa(),
                "\n\tbefore total shares:   ", beforeTotalShares.itoa(),
                "\n\tafter total shares:    ", afterTotalShares.itoa(),
                "\n\tbefore circulating:    ", beforeCirculating.itoa(),
                "\n\tafter circulating:     ", afterCirculating.itoa(),
                "\n\tbefore shares from:    ", beforeShares.itoa(),
                "\n\tafter shares from:     ", afterShares.itoa(),
                "\n\tbefore shares to:      ", beforeSharesTo.itoa(),
                "\n\tafter shares to:       ", afterSharesTo.itoa(),
                "\n\ttax (basis points):    ", tax.itoa()
            )
        );
        */

        // Check that the whale limit for each account "doesn't" change
        if (actor != pair && to != pair) {
            assertGe(saturatingAdd(afterWhaleLimit, 1), beforeWhaleLimit, "actor whale limit lower");
            assertLe(afterWhaleLimit, saturatingAdd(beforeWhaleLimit, 1), "actor whale limit upper");
            assertGe(saturatingAdd(afterWhaleLimitTo, 1), beforeWhaleLimitTo, "to whale limit lower");
            assertLe(afterWhaleLimitTo, saturatingAdd(beforeWhaleLimitTo, 1), "to whale limit upper");
        }

        // Check that the ratio between transferred tokens and burned tokens in the logs represents the tax rate
        assertGe(logAmountTransfer + logAmountBurn + 1, amount, "log amount lower");
        assertLe(logAmountTransfer + logAmountBurn, amount + 1, "log amount upper");
        if (
            afterCirculating < beforeCirculating
                || (afterCirculating - beforeCirculating) * (10_000 - tax) / 10_000
                    < beforeCirculating.unsafeDivUp(Settings.ANTI_WHALE_DIVISOR)
        ) {
            assertGe(
                ((logAmountTransfer + logAmountBurn) * tax).unsafeDivUp(10_000) + 2,
                logAmountBurn,
                "log tax ratio lower"
            );
            assertLe((logAmountTransfer + logAmountBurn) * tax / 10_000, logAmountBurn + 1, "log tax ratio upper");
        } else if (
            afterCirculating >= beforeCirculating
                && (afterCirculating - beforeCirculating) * (10_000 - tax) / 10_000
                    >= beforeCirculating.unsafeDivUp(Settings.ANTI_WHALE_DIVISOR)
        ) {
            assertLe(
                (logAmountTransfer + logAmountBurn) * tax / 10_000, logAmountBurn, "log tax ratio upper (insane whale)"
            );
        }

        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (log.topics[0] == IERC20.Transfer.selector) {
                assertEq(log.emitter, address(fu), "wrong log emitter");
                assertEq(log.topics.length, 3, "wrong topics");
                assertEq(log.data.length, 32, "wrong Transfer data length (amount)");
                assertEq(log.topics[1], bytes32(0), "wrong from address");
                assertLe(uint256(log.topics[2]), type(uint160).max, "dirty `to` topic");
                address rebaseTo = address(uint160(uint256(log.topics[2])));

                // TODO: we need to check the consistency of the queue with the
                // head, but this is complex because some elements of the queue
                // may be skipped (if their balances are nonincreasing) and also
                // the queue may be reordered (if the head pointed at `actor` or
                // `to`)

                uint256 rebaseAmountTokens = uint256(bytes32(log.data));
                uint256 rebaseAmountBalance =
                    rebaseAmountTokens * (uint160(rebaseTo) / Settings.ADDRESS_DIVISOR) / Settings.CRAZY_BALANCE_BASIS;
                uint256 rebaseOriginalBalance;
                uint256 rebaseNewBalance;
                if (rebaseTo == actor) {
                    rebaseOriginalBalance = originalBalance;
                    rebaseNewBalance = beforeBalance;
                } else if (rebaseTo == to) {
                    rebaseOriginalBalance = originalBalanceTo;
                    rebaseNewBalance = beforeBalanceTo;
                } else {
                    rebaseOriginalBalance = lastBalance[rebaseTo];
                    rebaseNewBalance = fu.balanceOf(rebaseTo);
                }
                console.log("original balance", rebaseOriginalBalance);
                console.log("new balance", rebaseNewBalance);
                uint256 rebaseBalanceDelta = rebaseNewBalance - rebaseOriginalBalance;
                console.log("rebaseBalanceDelta", rebaseBalanceDelta);
                console.log("rebaseAmountBalance", rebaseAmountBalance);
                //console.log("whaleLimit", fu.whaleLimit(rebaseTo));
                uint256 fudge = 2; // TODO: decrease
                if (!((rebaseTo == actor && toIsWhaleBefore) || (rebaseTo == to && actorIsWhale))) {
                    assertGe(
                        rebaseBalanceDelta + fudge,
                        rebaseAmountBalance,
                        string.concat("rebase delta lower: ", rebaseTo.toChecksumAddress())
                    );
                }
                if (rebaseTo == to ? !toIsWhale : rebaseNewBalance != fu.whaleLimit(rebaseTo)) {
                    assertLe(
                        rebaseBalanceDelta,
                        rebaseAmountBalance + fudge,
                        string.concat("rebase delta upper: ", rebaseTo.toChecksumAddress())
                    );
                }
            }
        }
        updateLastBalanceForRebaseQueue(logs, actor, to);

        // Check that the balance decrease of `actor` is the expected value
        if (!toIsWhaleBefore) {
            if (actor == pair || amount == beforeBalance) {
                assertEq(beforeBalance - afterBalance, amount, "from amount");
            } else {
                assertGe(beforeBalance - afterBalance + 1, amount, "from amount lower");
                assertLe(beforeBalance - afterBalance, amount + 1, "from amount upper");
            }
        } else {
            // It is possible for `actor`'s balance to increase if `to` was over the whale limit by
            // more than `amount`. Avoid underflow.
            if (beforeBalance >= afterBalance) {
                assertLe(beforeBalance - afterBalance, amount + 1, "from amount upper (to whale)");
            }
            assertTrue(toIsWhale, "to stopped being whale");
        }

        // Check that the balance increase of `to` is the expected value
        uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
        uint256 multiplier = uint160(to) / Settings.ADDRESS_DIVISOR;

        /*
        if (actor == pair) {
            divisor = 1;
        }
        if (to == pair) {
            multiplier = 1;
        }
        */

        if (beforeBalance >= afterBalance) {
            uint256 sendCrazyLo = beforeBalance - afterBalance;
            uint256 sendCrazyHi = amount;
            (sendCrazyLo, sendCrazyHi) =
                (sendCrazyLo > sendCrazyHi) ? (sendCrazyHi, sendCrazyLo) : (sendCrazyLo, sendCrazyHi);
            uint256 sendTokensLo;
            uint256 sendTokensHi;
            if (amount == beforeBalance) {
                (uint256 beforeSharesLimited,, uint256 beforeTotalSharesLimited) =
                    applyWhaleLimit(beforeShares, beforeSharesTo, beforeTotalShares);
                uint512 product = alloc().omul(beforeSharesLimited, beforeCirculating);
                sendTokensLo = product.div(beforeTotalSharesLimited);
                sendTokensHi = sendTokensLo.unsafeInc(tmp().omul(sendTokensLo, beforeTotalSharesLimited) < product);
            } else {
                sendTokensLo = sendCrazyLo * Settings.CRAZY_BALANCE_BASIS / divisor;
                sendTokensHi = (sendCrazyHi * Settings.CRAZY_BALANCE_BASIS).unsafeDivUp(divisor);
            }
            //console.log("sendTokensLo", sendTokensLo);
            //console.log("sendTokensHi", sendTokensHi);
            uint256 receiveTokensXBasisPointsLo = sendTokensLo * (10_000 - tax);
            uint256 receiveTokensXBasisPointsHi = sendTokensHi * (10_000 - tax);
            //console.log("receiveTokensXBasisPointsLo", receiveTokensXBasisPointsLo);
            //console.log("receiveTokensXBasisPointsHi", receiveTokensXBasisPointsHi);
            uint256 balanceDeltaLo = receiveTokensXBasisPointsLo * multiplier;
            uint256 balanceDeltaHi = receiveTokensXBasisPointsHi * multiplier;
            //console.log("balanceDeltaLo", balanceDeltaLo);
            //console.log("balanceDeltaHi", balanceDeltaHi);
            if (!toIsWhale) {
                assertGe(
                    (afterBalanceTo - beforeBalanceTo + 1) * (Settings.CRAZY_BALANCE_BASIS * 10_000)
                        + (Settings.CRAZY_BALANCE_BASIS * 10_000 / Settings.MIN_SHARES_RATIO - 1),
                    balanceDeltaLo,
                    "to delta lower"
                );
            } else {
                assertGe(
                    ((beforeBalanceTo + 1) * (Settings.CRAZY_BALANCE_BASIS * 10_000) + balanceDeltaHi).unsafeDivUp(
                        Settings.CRAZY_BALANCE_BASIS * 10_000
                    ),
                    afterWhaleLimitTo,
                    "not enough for `to` to become whale"
                );
                assertGe(afterBalanceTo + 1, beforeBalanceTo, "to balance lower (whale)");
            }
            if (!actorIsWhale) {
                if (afterBalanceTo >= beforeBalanceTo) {
                    assertLe(
                        (afterBalanceTo - beforeBalanceTo) * (Settings.CRAZY_BALANCE_BASIS * 10_000),
                        balanceDeltaHi + (Settings.CRAZY_BALANCE_BASIS * 10_000),
                        "to delta upper"
                    );
                } else {
                    assertTrue(toIsWhaleBefore, "to balance decrease not because whale");
                    assertTrue(toIsWhale, "to balance decrease not because whale");
                }
            }
        } else {
            assertTrue(toIsWhaleBefore);
        }

        // Check that the shares (not balance) accounting is reasonable. The consistency of
        // `totalShares` is checked by one of the invariants
        if (amount == 0) {
            if (to != pair || beforeBalance != 0) {
                assertEq(afterCirculating, beforeCirculating, "circulating");
            }
            if (actorIsWhale || toIsWhale) {
                assertGe(beforeTotalShares, afterTotalShares, "shares delta (whale)");
            } else if (beforeBalance == 0) {
                assertGe(beforeTotalShares, afterTotalShares, "shares delta upper (dust)");
                assertLe(beforeTotalShares - beforeShares, afterTotalShares, "shares delta lower (dust)");
            } else {
                assertEq(beforeTotalShares, afterTotalShares, "shares delta (no-op)");
            }
        } else {
            if (actor == pair) {
                assertGe(afterCirculating, beforeCirculating, "circulating (from pair)");
            } else if (to == pair) {
                assertLe(afterCirculating, beforeCirculating, "circulating (to pair)");
            } else {
                assertEq(afterCirculating, beforeCirculating, "circulating");
            }
            assertTrue(
                alloc().omul(beforeTotalShares, afterCirculating) > tmp().omul(afterTotalShares, beforeCirculating),
                "shares to tokens ratio increased"
            );
        }

        // Check that nobody went over the whale limit
        assertLe(
            afterShares,
            (afterTotalShares - afterShares) / Settings.ANTI_WHALE_DIVISOR_MINUS_ONE - 1,
            "from over whale limit"
        );
        assertLe(
            afterSharesTo,
            (afterTotalShares - afterSharesTo) / Settings.ANTI_WHALE_DIVISOR_MINUS_ONE - 1,
            "to over whale limit"
        );

        // This seems like it should be obvious, but let's check just to make sure; `actor` cannot
        // still be a whale if it sent any tokens
        if (amount > 1) {
            assertLt(afterBalance, afterWhaleLimit, "from is still a whale");
        }
    }

    function delegate(uint256 actorIndex, address delegatee) external {
        (address actor,) = super.getActor(actorIndex);
        assume(actor != pair);
        super.maybeCreateActor(delegatee);

        address oldDelegatee = shadowDelegates[actor];
        uint256 oldVotes = fu.getVotes(oldDelegatee);
        uint256 newVotes = fu.getVotes(delegatee);
        uint256 votes = getShares(actor) / Settings.SHARES_TO_VOTES_DIVISOR;
        expectEmit(true, true, true, true, address(fu));
        emit IERC5805.DelegateChanged(actor, oldDelegatee, delegatee);
        if (votes != 0 && oldDelegatee != delegatee) {
            if (oldDelegatee != address(0)) {
                expectEmit(true, true, true, true, address(fu));
                emit IERC5805.DelegateVotesChanged(oldDelegatee, oldVotes, oldVotes - votes);
            }
            if (delegatee != address(0)) {
                expectEmit(true, true, true, true, address(fu));
                emit IERC5805.DelegateVotesChanged(delegatee, newVotes, newVotes + votes);
            }
        }

        prank(actor);
        fu.delegate(delegatee); // ERC5805 requires that this function return nothing or revert

        assertEq(fu.delegates(actor), delegatee);

        super.saveActor(actor);
        shadowDelegates[actor] = fu.delegates(actor);
        if (delegatee != address(0) && delegatee != DEAD && delegatee != address(fu)) {
            super.saveActor(delegatee);
        }
    }

    function _burnShouldFail(address from, uint256 amount, uint256 balance) internal pure returns (bool) {
        return from == DEAD || amount > balance;
    }

    function burn(uint256 actorIndex, uint256 amount, bool boundAmount) external {
        (address actor, uint256 originalBalance) = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
        } else {
            console.log("amount", amount);
        }
        assume(actor != pair || amount == 0);

        address delegatee = shadowDelegates[actor];

        uint256 beforeBalance = lastBalance[actor];
        uint256 beforeWhaleLimit = fu.whaleLimit(actor);
        uint256 beforeSupply = fu.totalSupply();
        uint256 beforeTotalShares = getTotalShares();
        uint256 beforeCirculating = getCirculatingTokens();
        uint256 beforeVotingPower = fu.getVotes(delegatee);
        uint256 beforeShares = getShares(actor);

        if (!_burnShouldFail(actor, amount, beforeBalance)) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Transfer(actor, address(0), amount);
            uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
            uint256 votes = divisor == 0
                ? 0
                : tmp().omul(amount * Settings.CRAZY_BALANCE_BASIS, beforeTotalShares).div(
                    beforeCirculating * divisor * Settings.SHARES_TO_VOTES_DIVISOR
                );
            address actorDelegatee = fu.delegates(actor);
            // TODO: `votes > 1` should be `votes != 0`, but there appears to be some rounding error in play here.
            if (votes > 1 && actorDelegatee != address(0)) {
                expectEmit(true, true, true, false, address(fu));
                emit IERC5805.DelegateVotesChanged(actorDelegatee, type(uint256).max, type(uint256).max);
            }
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.burn, (amount)));
        assertEq(success, !_burnShouldFail(actor, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            restoreActor(actor, originalBalance);
            return;
        }

        saveActor(actor);

        uint256 afterBalance = lastBalance[actor];
        uint256 afterSupply = fu.totalSupply();
        uint256 afterTotalShares = getTotalShares();
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterVotingPower = fu.getVotes(delegatee);
        uint256 afterShares = getShares(actor);

        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (log.topics[0] == IERC20.Transfer.selector && log.topics[1] == bytes32(0)) {
                assertEq(log.emitter, address(fu), "wrong log emitter");
                assertEq(log.topics.length, 3, "wrong topics");
                assertEq(log.data.length, 32, "wrong Transfer data length (amount)");
                assertLe(uint256(log.topics[2]), type(uint160).max, "dirty `to` topic");
                address rebaseTo = address(uint160(uint256(log.topics[2])));

                // TODO: see TODO in similar block in `transfer`

                uint256 rebaseAmountTokens = uint256(bytes32(log.data));
                uint256 rebaseAmountBalance =
                    rebaseAmountTokens * (uint160(rebaseTo) / Settings.ADDRESS_DIVISOR) / Settings.CRAZY_BALANCE_BASIS;
                uint256 rebaseOriginalBalance;
                uint256 rebaseNewBalance;
                if (rebaseTo == actor) {
                    rebaseOriginalBalance = originalBalance;
                    rebaseNewBalance = beforeBalance;
                } else {
                    rebaseOriginalBalance = lastBalance[rebaseTo];
                    rebaseNewBalance = fu.balanceOf(rebaseTo);
                }
                console.log("original balance", rebaseOriginalBalance);
                console.log("new balance", rebaseNewBalance);
                uint256 rebaseBalanceDelta = rebaseNewBalance - rebaseOriginalBalance;
                console.log("rebaseBalanceDelta", rebaseBalanceDelta);
                console.log("rebaseAmountBalance", rebaseAmountBalance);
                //console.log("whaleLimit", fu.whaleLimit(rebaseTo));
                uint256 fudge = 2; // TODO: decrease
                assertGe(
                    rebaseBalanceDelta + fudge,
                    rebaseAmountBalance,
                    string.concat("rebase delta lower: ", rebaseTo.toChecksumAddress())
                );
                if (rebaseNewBalance != fu.whaleLimit(rebaseTo)) {
                    assertLe(
                        rebaseBalanceDelta,
                        rebaseAmountBalance + fudge,
                        string.concat("rebase delta upper: ", rebaseTo.toChecksumAddress())
                    );
                }
            }
        }
        updateLastBalanceForRebaseQueue(logs, actor);

        if (beforeShares == 0) {
            assertTrue(
                alloc().omul(beforeTotalShares, afterCirculating) == tmp().omul(afterTotalShares, beforeCirculating),
                "shares to tokens ratio (no shares)"
            );
        } else if (beforeBalance == 0) {
            assertTrue(
                alloc().omul(beforeTotalShares, afterCirculating) > tmp().omul(afterTotalShares, beforeCirculating),
                "shares to tokens ratio (dust)"
            );
        } else if (amount == 0) {
            if (beforeBalance != beforeWhaleLimit) {
                assertTrue(
                    alloc().omul(beforeTotalShares, afterCirculating) == tmp().omul(afterTotalShares, beforeCirculating),
                    "shares to tokens ratio (zero)"
                );
            }
        } else {
            assertTrue(
                alloc().omul(beforeTotalShares, afterCirculating) >= tmp().omul(afterTotalShares, beforeCirculating),
                "shares to tokens ratio increased (base case)"
            );
        }

        if (delegatee != address(0)) {
            assertEq(
                beforeVotingPower - afterVotingPower,
                beforeShares / Settings.SHARES_TO_VOTES_DIVISOR - afterShares / Settings.SHARES_TO_VOTES_DIVISOR,
                "voting power delta mismatch"
            );
        } else {
            assertEq(beforeVotingPower, afterVotingPower, "no delegation, but voting power changed");
        }

        assertLe(beforeBalance - afterBalance, amount + 1, "balance delta upper");
        assertGe(beforeBalance - afterBalance + 1, amount, "balance delta lower");
        uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
        if (divisor == 0) {
            assertEq(amount, 0, "efficient address edge case");
            assertEq(beforeSupply, afterSupply, "efficient address edge case supply");
            return;
        }

        if (amount == beforeBalance) {
            assertLe(
                beforeSupply - afterSupply, (amount + 1) * Settings.CRAZY_BALANCE_BASIS / divisor, "supply delta higher"
            );
            assertGe(beforeSupply - afterSupply, amount * Settings.CRAZY_BALANCE_BASIS / divisor, "supply delta lower");
        } else {
            assertEq(beforeSupply - afterSupply, amount * Settings.CRAZY_BALANCE_BASIS / divisor, "supply delta");
        }
    }

    function _deliverShouldFail(address from, uint256 amount, uint256 balance) internal pure returns (bool) {
        return from == DEAD || amount > balance;
    }

    function deliver(uint256 actorIndex, uint256 amount, bool boundAmount) external {
        (address actor, uint256 originalBalance) = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
        } else {
            console.log("amount", amount);
        }
        assume(actor != pair || amount == 0);

        uint256 beforeBalance = lastBalance[actor];
        uint256 beforeWhaleLimit = fu.whaleLimit(actor);
        bool actorIsWhale = beforeBalance == beforeWhaleLimit;
        uint256 beforeShares = getShares(actor);
        uint256 beforeCirculating = getCirculatingTokens();
        uint256 beforeTotalShares = getTotalShares();

        if (!_deliverShouldFail(actor, amount, beforeBalance)) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Transfer(actor, address(0), amount);
            uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
            uint256 votes = divisor == 0
                ? 0
                : tmp().omul(amount * Settings.CRAZY_BALANCE_BASIS, beforeTotalShares).div(
                    beforeCirculating * divisor * Settings.SHARES_TO_VOTES_DIVISOR
                );
            address actorDelegatee = fu.delegates(actor);
            // TODO: `votes > 1` should be `votes != 0`, but there appears to be some rounding error in play here.
            if (votes > 1 && actorDelegatee != address(0)) {
                expectEmit(true, true, true, false, address(fu));
                emit IERC5805.DelegateVotesChanged(actorDelegatee, type(uint256).max, type(uint256).max);
            }
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.deliver, (amount)));
        assertEq(success, !_deliverShouldFail(actor, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            restoreActor(actor, originalBalance);
            return;
        }

        saveActor(actor);

        uint256 afterWhaleLimit = fu.whaleLimit(actor);
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterTotalShares = getTotalShares();

        for (uint256 i; i < logs.length; i++) {
            VmSafe.Log memory log = logs[i];
            if (log.topics[0] == IERC20.Transfer.selector && log.topics[1] == bytes32(0)) {
                assertEq(log.emitter, address(fu), "wrong log emitter");
                assertEq(log.topics.length, 3, "wrong topics");
                assertEq(log.data.length, 32, "wrong Transfer data length (amount)");
                assertLe(uint256(log.topics[2]), type(uint160).max, "dirty `to` topic");
                address rebaseTo = address(uint160(uint256(log.topics[2])));

                // TODO: see TODO in similar block in `transfer`

                uint256 rebaseAmountTokens = uint256(bytes32(log.data));
                uint256 rebaseAmountBalance =
                    rebaseAmountTokens * (uint160(rebaseTo) / Settings.ADDRESS_DIVISOR) / Settings.CRAZY_BALANCE_BASIS;
                uint256 rebaseOriginalBalance;
                uint256 rebaseNewBalance;
                if (rebaseTo == actor) {
                    rebaseOriginalBalance = originalBalance;
                    rebaseNewBalance = beforeBalance;
                } else {
                    rebaseOriginalBalance = lastBalance[rebaseTo];
                    rebaseNewBalance = fu.balanceOf(rebaseTo);
                }
                console.log("original balance", rebaseOriginalBalance);
                console.log("new balance", rebaseNewBalance);
                uint256 rebaseBalanceDelta = rebaseNewBalance - rebaseOriginalBalance;
                console.log("rebaseBalanceDelta", rebaseBalanceDelta);
                console.log("rebaseAmountBalance", rebaseAmountBalance);
                //console.log("whaleLimit", fu.whaleLimit(rebaseTo));
                uint256 fudge = 2; // TODO: decrease
                assertGe(
                    rebaseBalanceDelta + fudge,
                    rebaseAmountBalance,
                    string.concat("rebase delta lower: ", rebaseTo.toChecksumAddress())
                );
                if (rebaseNewBalance != fu.whaleLimit(rebaseTo)) {
                    assertLe(
                        rebaseBalanceDelta,
                        rebaseAmountBalance + fudge,
                        string.concat("rebase delta upper: ", rebaseTo.toChecksumAddress())
                    );
                }
            }
        }
        updateLastBalanceForRebaseQueue(logs, actor);

        assertGe(saturatingAdd(afterWhaleLimit, 1), beforeWhaleLimit, "whale limit lower");
        assertLe(afterWhaleLimit, saturatingAdd(beforeWhaleLimit, 1), "whale limit upper");
        assertEq(afterCirculating, beforeCirculating, "circulating tokens changed");

        if (amount == 0) {
            if (actorIsWhale) {
                assertGe(beforeTotalShares, afterTotalShares, "shares delta (whale)");
            } else if (beforeBalance == 0) {
                assertEq(beforeTotalShares - beforeShares, afterTotalShares, "shares delta (dust)");
            } else {
                assertEq(beforeTotalShares, afterTotalShares, "shares delta (no-op)");
            }
        } else {
            assertTrue(
                alloc().omul(beforeTotalShares, afterCirculating) > tmp().omul(afterTotalShares, beforeCirculating),
                "shares to tokens ratio increased"
            );
        }
    }

    function invariant_nonNegativeRebase() external view override {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            uint256 balance = fu.balanceOf(actor);
            if (uint160(actor) < Settings.ADDRESS_DIVISOR) {
                assertEq(balance, 0);
                assertEq(lastBalance[actor], 0);
                continue;
            }
            uint256 whaleLimit = fu.whaleLimit(actor);
            assertLe(balance, whaleLimit, string.concat("whale limit exceeded: ", actor.toChecksumAddress()));
            if (balance != whaleLimit) {
                assertGe(balance, lastBalance[actor], string.concat("negative rebase: ", actor.toChecksumAddress()));
            }
        }
        assertGe(fu.balanceOf(DEAD), lastBalance[DEAD], "negative rebase: DEAD");
    }

    function invariant_delegatesNotChanged() external view override {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            assertEq(fu.delegates(actor), shadowDelegates[actor], "delegates mismatch");
        }
    }

    function invariant_sumOfShares() external view override {
        uint256 total = getShares(DEAD);
        for (uint256 i; i < actors.length; i++) {
            total += getShares(actors[i]);
        }
        assertEq(total, getTotalShares(), "sum(shares) mismatch with totalShares");
    }

    function _smuggle(function () internal contraband) internal pure returns (function () internal pure smuggled) {
        assembly ("memory-safe") {
            smuggled := contraband
        }
    }

    function _invariant_votingDelegation() internal {
        uint256 total;
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            address delegatee = shadowDelegates[actor];
            if (delegatee == address(0)) {
                continue;
            }
            uint256 shares = getShares(actor);
            uint256 votes = shares / Settings.SHARES_TO_VOTES_DIVISOR;
            total += votes;
            assembly ("memory-safe") {
                delegatee := and(0xffffffffffffffffffffffffffffffffffffffff, delegatee)
                tstore(delegatee, add(votes, tload(delegatee)))
            }
        }
        assertEq(fu.getTotalVotes(), total);
        {
            uint256 power;
            assembly ("memory-safe") {
                power := tload(DEAD)
                tstore(DEAD, 0x00)
            }
            total -= power;
            assertEq(fu.getVotes(DEAD), power, string.concat("voting power for ", DEAD.toChecksumAddress()));
        }
        {
            uint256 power;
            address fu_ = address(fu);
            assembly ("memory-safe") {
                fu_ := and(0xffffffffffffffffffffffffffffffffffffffff, fu_)
                power := tload(fu_)
                tstore(fu_, 0x00)
            }
            total -= power;
            assertEq(fu.getVotes(fu_), power, string.concat("voting power for ", fu_.toChecksumAddress()));
        }
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            uint256 power;
            assembly ("memory-safe") {
                actor := and(0xffffffffffffffffffffffffffffffffffffffff, actor)
                power := tload(actor)
                tstore(actor, 0x00)
            }
            total -= power;
            assertEq(fu.getVotes(actor), power, string.concat("voting power for ", actor.toChecksumAddress()));
        }
        assertEq(total, 0);
    }

    function invariant_votingDelegation() external view override {
        return _smuggle(_invariant_votingDelegation)();
    }

    function invariant_delegateeZero() external view override {
        assertEq(fu.getVotes(address(0)), 0, "zero cannot have voting power");
    }

    function _invariant_rebaseQueueContents() internal {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            assembly ("memory-safe") {
                tstore(and(0xffffffffffffffffffffffffffffffffffffffff, actor), 0x01)
            }
        }

        address head = address(uint160(uint256(load(address(fu), bytes32(uint256(BASE_SLOT) + 4)))));
        uint256 length;
        bool deadOnQueue;
        for (address cursor = head;;) {
            assertNotEq(
                getShares(cursor), 0, string.concat("zero shares account ", cursor.toChecksumAddress(), " on queue")
            );

            if (cursor != DEAD) {
                length++;

                bool condition;
                assembly ("memory-safe") {
                    cursor := and(0xffffffffffffffffffffffffffffffffffffffff, cursor)
                    condition := tload(cursor)
                    tstore(cursor, 0x00)
                }
                assertTrue(condition, string.concat("non-actor ", cursor.toChecksumAddress(), " on rebase queue"));
            } else {
                assertFalse(deadOnQueue, "duplicate dead entry (multicycle?)");
                deadOnQueue = true;
            }

            address cursorNext = getRebaseQueueNext(cursor);
            assertEq(getRebaseQueuePrev(cursorNext), cursor, "prev pointer mismatch");
            if (cursorNext == head) {
                break;
            }
            cursor = cursorNext;
        }

        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];

            bool condition;
            assembly ("memory-safe") {
                actor := and(0xffffffffffffffffffffffffffffffffffffffff, actor)
                condition := tload(actor)
                tstore(actor, 0x00)
            }

            if (actor == pair) {
                assertTrue(condition, "pair is not allowed on rebase queue");
            }

            if (condition) {
                length++;
                assertEq(
                    getShares(actor),
                    0,
                    string.concat("nonzero shares account ", actor.toChecksumAddress(), " not on queue")
                );
            }
        }

        assertTrue(deadOnQueue, "dead is not on the queue");
        assertEq(length, actors.length, "length mismatch");
    }

    function invariant_rebaseQueueContents() external view override {
        return _smuggle(_invariant_rebaseQueueContents)();
    }
}

contract FUInvariants is FUDeploy, StdInvariant, ListOfInvariants {
    using ChecksumAddress for address;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code"))))); // TODO: remove

    bool public constant IS_TEST = true;
    FUGuide internal guide;

    function setUp() public virtual override {
        super.setUp();
        excludeContract(address(fu));
        excludeContract(address(buyback));
        excludeContract(fu.pair());
        excludeContract(address(WETH));
        excludeContract(address(UNIV2_FACTORY));
        guide = new FUGuide(fu, buyback, actors);
    }

    function test_name() external view {
        assertEq(fu.name(), "Fuck You!");
    }

    function test_symbol() external {
        assertEq(fu.symbol(), string.concat("Fuck you, ", address(this).toChecksumAddress(), "!"));
        vm.prank(address(this), address(0)); // TODO: incompatible with medusa
        assertEq(fu.symbol(), "FU");
    }

    function test_decimals() external view {
        assertEq(fu.decimals(), 35);
    }

    function invariant_nonNegativeRebase() public virtual override {
        return ListOfInvariants(guide).invariant_nonNegativeRebase();
    }

    function invariant_delegatesNotChanged() public virtual override {
        return ListOfInvariants(guide).invariant_delegatesNotChanged();
    }

    function invariant_sumOfShares() public virtual override {
        return ListOfInvariants(guide).invariant_sumOfShares();
    }

    function invariant_votingDelegation() public virtual override {
        return ListOfInvariants(guide).invariant_votingDelegation();
    }

    function invariant_delegateeZero() public virtual override {
        return ListOfInvariants(guide).invariant_delegateeZero();
    }

    function invariant_rebaseQueueContents() public virtual override {
        return ListOfInvariants(guide).invariant_rebaseQueueContents();
    }

    function invariant_vacuous() external pure {}
}
