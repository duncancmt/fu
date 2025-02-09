// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {FU} from "src/FU.sol";
import {Buyback} from "src/Buyback.sol";
import {Settings} from "src/core/Settings.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory, pairFor} from "src/interfaces/IUniswapV2Factory.sol";
import {ChecksumAddress} from "src/lib/ChecksumAddress.sol";
import {UnsafeMath} from "src/lib/UnsafeMath.sol";
import {alloc, tmp} from "src/lib/512Math.sol";

import {QuickSort} from "script/QuickSort.sol";
import {ItoA} from "script/ItoA.sol";
import {Hexlify} from "script/Hexlify.sol";

import {StdAssertions} from "@forge-std/StdAssertions.sol";
import {StdInvariant} from "@forge-std/StdInvariant.sol";
import {VmSafe, Vm} from "@forge-std/Vm.sol";

import "./EnvironmentConstants.sol";

import {console} from "@forge-std/console.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
uint256 constant EPOCH = 1740721485;

abstract contract Common {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assume(bool condition) internal pure virtual {
        vm.assume(condition);
    }

    function label(address target, string memory name) internal virtual {
        vm.label(target, name);
    }

    function prank(address sender) internal virtual {
        vm.prank(sender);
    }

    function setNonce(address who, uint64 newNonce) internal virtual {
        vm.setNonce(who, newNonce);
    }

    function deal(address who, uint256 value) internal virtual {
        vm.deal(who, value);
    }

    function setBaseFee(uint256 newBaseFee) internal {
        vm.fee(newBaseFee);
    }

    function setChainId(uint256 newChainId) internal {
        vm.chainId(newChainId);
    }

    function warp(uint256 newTimestamp) internal {
        vm.warp(newTimestamp);
    }

    function getBlockTimestamp() internal view returns (uint256) {
        return vm.getBlockTimestamp();
    }

    function load(address account, bytes32 slot) internal view returns (bytes32) {
        return vm.load(account, slot);
    }

    function store(address account, bytes32 slot, bytes32 newValue) internal {
        return vm.store(account, slot, newValue);
    }
}

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

interface ListOfInvariants {
    function invariant_nonNegativeRebase() external;
    function invariant_delegatesNotChanged() external;
    function invariant_sumOfShares() external;
    function invariant_votingDelegation() external;
    function invariant_delegateeZero() external;
}

contract FUGuide is StdAssertions, Common, Bound, ListOfInvariants {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code"))))); // TODO: remove

    using ItoA for uint256;
    using ChecksumAddress for address;
    using UnsafeMath for uint256;

    IFU internal immutable fu;
    address internal immutable pair;
    address[] internal actors;
    mapping(address => bool) internal isActor;
    mapping(address => uint256) internal lastBalance;
    mapping(address => address) internal shadowDelegates;
    uint32 internal shareRatio = 1;

    constructor(IFU fu_, address[] memory actors_) {
        fu = fu_;
        pair = fu.pair();
        actors = actors_;

        lastBalance[DEAD] = fu.balanceOf(DEAD);
        actors.push(pair);

        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            isActor[actor] = true;
            lastBalance[actor] = fu.balanceOf(actor);
        }
    }

    function callOptionalReturn(bytes memory data) internal returns (bool success, bytes memory returndata) {
        (success, returndata) = address(fu).call(data);
        success = success && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    bytes32 private constant _BASE_SLOT = 0x00000000000000000000000000000000e086ec3a639808bbda893d5b4ac93600;

    function _sharesSlot(address account) internal pure returns (bytes32 r) {
        assembly ("memory-safe") {
            mstore(0x00, and(0xffffffffffffffffffffffffffffffffffffffff, account))
            mstore(0x20, add(_BASE_SLOT, 7))
            r := keccak256(0x00, 0x40)
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
        uint256 value = uint256(load(address(fu), bytes32(uint256(_BASE_SLOT) + 2)));
        assertEq(value >> 177, 0, string.concat("dirty total supply slot: ", value.itoa()));
        assertNotEq(value, 0, "zero total shares");
        return value;
    }

    function setTotalShares(uint256 newTotalShares) internal {
        assertNotEq(newTotalShares, 0, "cannot set zero total shares");
        return store(address(fu), bytes32(uint256(_BASE_SLOT) + 2), bytes32(newTotalShares));
    }

    function getCirculatingTokens() internal view returns (uint256) {
        uint256 value = uint256(load(address(fu), _BASE_SLOT));
        assertEq(value >> 145, 0, string.concat("dirty circulating tokens slot: ", value.itoa()));
        assertNotEq(value, 0, "zero circulating tokens");
        return value;
    }

    function getActor(uint256 actorIndex) internal returns (address actor) {
        actor = actors[actorIndex % actors.length];
        lastBalance[actor] = fu.balanceOf(actor);
        console.log("actor", actor);
    }

    function maybeCreateActor(address newActor) internal {
        // TODO: change naming here as this may not be a new actor
        if (newActor == DEAD) {
            return;
        }
        if (isActor[newActor]) {
            return;
        }

        // turn potential actor into a new actor as this passes all checks and is not, in fact, sussy
        isActor[newActor] = true;
        actors.push(newActor);
        assertEq(fu.balanceOf(newActor), 0);
        assertEq(fu.delegates(newActor), address(0));
    }

    function saveActor(address actor) internal {
        assertNotEq(actor, DEAD);
        assertTrue(isActor[actor]);
        lastBalance[actor] = fu.balanceOf(actor);
        shadowDelegates[actor] = fu.delegates(actor);
    }

    function addActor(address newActor) external {
        assume(newActor != DEAD);
        assume(!isActor[newActor]);
        maybeCreateActor(newActor);
        saveActor(newActor);
    }

    function warp(uint24 incr) external {
        assume(incr > 0);
        warp(getBlockTimestamp() + incr);
    }

    function setSharesRatio(uint32 newRatio) external {
        uint32 oldRatio = shareRatio;
        uint256 fudge = 10; // TODO: decrease
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

            address delegatee = shadowDelegates[actor];
            if (delegatee != address(0)) {
                prank(actor);
                fu.delegate(address(0));
            }

            uint256 shares = getShares(actor) * oldRatio / newRatio;
            total += shares;
            setShares(actor, shares);

            if (delegatee != address(0)) {
                prank(actor);
                fu.delegate(delegatee);
            }
        }
        setTotalShares(total);

        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            lastBalance[actor] = fu.balanceOf(actor);
        }

        shareRatio = newRatio;
    }

    function _assertNoMutation(VmSafe.AccountAccess[] memory accountAccesses, VmSafe.Log[] memory logs) internal pure {
        assertEq(logs.length, 0, "emitted event on failure");
        for (uint256 i; i < accountAccesses.length; i++) {
            VmSafe.AccountAccess memory accountAccess = accountAccesses[i];
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.CallCode), "CALLCODE");
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.Create), "CREATE");
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.SelfDestruct), "SELFDESTRUCT");
            assertEq(accountAccess.oldBalance, accountAccess.newBalance, "modified balance");
            assertEq(accountAccess.value, 0, "sent ETH");
            VmSafe.StorageAccess[] memory storageAccesses = accountAccess.storageAccesses;
            for (uint256 j; j < storageAccesses.length; j++) {
                VmSafe.StorageAccess memory storageAccess = storageAccesses[j];
                assertFalse(storageAccess.isWrite, "wrote storage");
            }
        }
    }

    function _transferShouldFail(address from, address to, uint256 amount, uint256 balance) internal view returns (bool) {
        return from == DEAD || to == DEAD || to == address(fu) || to == from || amount > balance || uint160(to) / Settings.ADDRESS_DIVISOR == 0;
    }

    function transfer(uint256 actorIndex, address to, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
        }
        if (actor == pair) {
            assume(amount < fu.balanceOf(actor));
        }
        maybeCreateActor(to);

        uint256 beforeBalance = lastBalance[actor];
        uint256 beforeBalanceTo = fu.balanceOf(to);
        uint256 beforeWhaleLimit = fu.whaleLimit(actor);
        uint256 beforeWhaleLimitTo = fu.whaleLimit(to);
        bool actorIsWhale = beforeBalance == beforeWhaleLimit;
        bool toIsWhaleBefore = beforeBalanceTo == beforeWhaleLimitTo;
        uint256 beforeShares = getShares(actor);
        uint256 beforeSharesTo = getShares(to);
        uint256 beforeCirculating = getCirculatingTokens();
        uint256 beforeTotalShares = getTotalShares();
        uint256 tax = fu.tax();

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);
        // TODO: expect events
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.transfer, (to, amount)));
        assertNotEq(success, _transferShouldFail(actor, to, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // TODO: handle failure
        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            _assertNoMutation(accountAccesses, logs);
            return;
        }

        saveActor(actor);
        saveActor(to);

        // TODO: check for "rebase queue" events

        uint256 afterBalance = lastBalance[actor];
        uint256 afterBalanceTo = lastBalance[to];
        uint256 afterWhaleLimit = fu.whaleLimit(actor);
        uint256 afterWhaleLimitTo = fu.whaleLimit(to);
        bool toIsWhale = afterBalanceTo == afterWhaleLimitTo;
        uint256 afterShares = getShares(actor);
        uint256 afterSharesTo = getShares(to);
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterTotalShares = getTotalShares();

        if (actor != pair && to != pair) {
            assertGe(saturatingAdd(afterWhaleLimit, 1), beforeWhaleLimit, "actor whale limit lower");
            assertLe(afterWhaleLimit, saturatingAdd(beforeWhaleLimit, 1), "actor whale limit upper");
            assertGe(saturatingAdd(afterWhaleLimitTo, 1), beforeWhaleLimitTo, "to whale limit lower");
            assertLe(afterWhaleLimitTo, saturatingAdd(beforeWhaleLimitTo, 1), "to whale limit upper");
        }

        if (!toIsWhaleBefore) {
            if (actor == pair || amount == beforeBalance) {
                assertEq(beforeBalance - afterBalance, amount, "from amount");
            } else {
                assertGe(beforeBalance - afterBalance + 1, amount, "from amount lower");
                assertLe(beforeBalance - afterBalance, amount + 1, "from amount upper");
            }
        }

        uint256 divisor = uint160(actor) / Settings.ADDRESS_DIVISOR;
        if (divisor != 0) {
            uint256 multiplier = uint160(to) / Settings.ADDRESS_DIVISOR;

            /*
            if (actor == pair) {
                divisor = 1;
            }
            if (to == pair) {
                multiplier = 1;
            }
            */

            uint256 sendCrazyLo = beforeBalance - afterBalance;
            uint256 sendCrazyHi = amount;
            (sendCrazyLo, sendCrazyHi) = (sendCrazyLo > sendCrazyHi) ? (sendCrazyHi, sendCrazyLo) : (sendCrazyLo, sendCrazyHi);
            uint256 sendTokensLo = sendCrazyLo * Settings.CRAZY_BALANCE_BASIS / divisor;
            uint256 sendTokensHi = ((sendCrazyHi + 1) * Settings.CRAZY_BALANCE_BASIS - 1) / divisor;
            uint256 receiveTokensXBasisPointsLo = sendTokensLo * 10_000 - (sendTokensLo * tax);
            uint256 receiveTokensXBasisPointsHi = sendTokensHi * (10_000 - tax);
            uint256 balanceDeltaLo = receiveTokensXBasisPointsLo * multiplier / (Settings.CRAZY_BALANCE_BASIS * 10_000);
            uint256 balanceDeltaHi = (receiveTokensXBasisPointsHi * multiplier).unsafeDivUp(Settings.CRAZY_BALANCE_BASIS * 10_000);
            if (!toIsWhale) {
                assertGe(afterBalanceTo - beforeBalanceTo + 1, balanceDeltaLo, "to delta lower");
            }
            if (!actorIsWhale) {
                assertLe(afterBalanceTo - beforeBalanceTo, balanceDeltaHi + 1, "to delta upper");
            }
        } else {
            assertEq(afterBalanceTo, beforeBalanceTo);
        }

        if (amount == 0) {
            assertEq(afterCirculating, beforeCirculating);
            if (actorIsWhale || toIsWhale) {
                assertGe(beforeTotalShares, afterTotalShares, "shares delta (whale)");
            } else if (beforeBalance == 0) {
                assertGe(beforeTotalShares, afterTotalShares, "shares delta upper (dust)");
                assertLe(beforeTotalShares - beforeShares, afterTotalShares, "shares delta lower (dust)");
            } else {
                assertEq(beforeTotalShares, afterTotalShares, "shares delta (no-op)");
            }
        } else {
            assertTrue(alloc().omul(beforeTotalShares, afterCirculating) > tmp().omul(afterTotalShares, beforeCirculating), "shares to tokens ratio increased");
        }

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
    }

    function delegate(uint256 actorIndex, address delegatee) external {
        address actor = getActor(actorIndex);
        assume(actor != pair);
        maybeCreateActor(delegatee);

        prank(actor);
        // TODO: expect events
        fu.delegate(delegatee); // ERC5805 requires that this function return nothing or revert

        saveActor(actor);
        if (delegatee != DEAD) {
            saveActor(delegatee);
        }
    }

    function _burnShouldFail(address from, uint256 amount, uint256 balance) internal pure returns (bool) {
        return from == DEAD || amount > balance;
    }

    function burn(uint256 actorIndex, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
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

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);
        // TODO: expect events
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.burn, (amount)));
        assertNotEq(success, _burnShouldFail(actor, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // TODO: handle failure
        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            _assertNoMutation(accountAccesses, logs);
            return;
        }

        saveActor(actor);

        // TODO: check for "rebase queue" events

        uint256 afterBalance = lastBalance[actor];
        uint256 afterSupply = fu.totalSupply();
        uint256 afterTotalShares = getTotalShares();
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterVotingPower = fu.getVotes(delegatee);
        uint256 afterShares = getShares(actor);

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
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor), "amount");
        }
        assume(actor != pair || amount == 0);

        uint256 beforeBalance = lastBalance[actor];
        uint256 beforeWhaleLimit = fu.whaleLimit(actor);
        bool actorIsWhale = beforeBalance == beforeWhaleLimit;
        uint256 beforeShares = getShares(actor);
        uint256 beforeCirculating = getCirculatingTokens();
        uint256 beforeTotalShares = getTotalShares();

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);
        // TODO: expect events
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.deliver, (amount)));
        assertNotEq(success, _deliverShouldFail(actor, amount, beforeBalance), "unexpected failure");

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // TODO: handle failure
        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            _assertNoMutation(accountAccesses, logs);
            return;
        }

        saveActor(actor);

        // TODO: check for "rebase queue" events

        uint256 afterWhaleLimit = fu.whaleLimit(actor);
        uint256 afterCirculating = getCirculatingTokens();
        uint256 afterTotalShares = getTotalShares();

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

    // TODO: permit
    // TODO: delegateBySig
    // TODO: allowance logic (transferFrom, deliverFrom, burnFrom)
    // TODO: checkpointing logic

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
            if (actor != pair) {
                assertLe(balance, whaleLimit, string.concat("whale limit exceeded: ", actor.toChecksumAddress()));
            }
            if (balance != whaleLimit) {
                assertGe(balance, lastBalance[actor], string.concat("negative rebase: ", actor.toChecksumAddress()));
            }
        }
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

    function invariant_votingDelegation() external override {
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

    function invariant_delegateeZero() external view override {
        assertEq(fu.getVotes(address(0)), 0, "zero cannot have voting power");
    }
}

contract FUInvariants is StdInvariant, Common, ListOfInvariants {
    using QuickSort for address[];
    using Hexlify for bytes32;

    bool public constant IS_TEST = true;
    FUGuide internal guide;

    function deployFuDependenciesFoundry() internal {
        // Deploy WETH
        bytes memory initcode = wethInit;
        setNonce(wethDeployer, wethDeployerNonce);
        prank(wethDeployer);
        assembly ("memory-safe") {
            if xor(weth, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(weth, "WETH");
        excludeContract(weth);

        // Deploy the UniswapV2 factory
        initcode = univ2FactoryInit;
        setNonce(univ2FactoryDeployer, univ2FactoryDeployerNonce);
        prank(univ2FactoryDeployer);
        assembly ("memory-safe") {
            if xor(univ2Factory, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(univ2Factory, "Uniswap V2 Factory");
        excludeContract(univ2Factory);

        // Optionally deploy the deployment proxy, if it doesn't exist
        if (deterministicDeployerFactory.codehash != 0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989)
        {
            initcode = deterministicDeployerFactoryInit;
            setNonce(deterministicDeployerFactoryDeployer, deterministicDeployerFactoryDeployerNonce);
            prank(deterministicDeployerFactoryDeployer);
            assembly ("memory-safe") {
                if xor(deterministicDeployerFactory, create(0x00, add(0x20, initcode), mload(initcode))) {
                    revert(0x00, 0x00)
                }
            }
            label(deterministicDeployerFactory, "Create2Deployer");
        }
    }

    /*
    function deployFuDependenciesMedusa() internal {
        // Deploy WETH
        vm.etch(weth, wethRuntime);
        label(weth, "WETH");

        // Deploy the UniswapV2 factory
        vm.etch(univ2Factory, univ2FactoryRuntime);
        vm.store(univ2Factory, bytes32(uint256(1)), bytes32(uint256(uint160(univ2FactoryFeeToSetter))));
        label(univ2Factory, "Uniswap V2 Factory");

        // Deploy the deterministic deployer factory
        vm.etch(deterministicDeployerFactory, deterministicDeployerFactoryRuntime);
        label(deterministicDeployerFactory, "Create2Deployer");
    }
    */

    function deployFuDependencies() internal virtual {
        return deployFuDependenciesFoundry();
    }

    function deployFu() internal returns (IFU fu, Buyback buyback, address[] memory initialHolders) {
        initialHolders = new address[](Settings.ANTI_WHALE_DIVISOR * 2);
        for (uint256 i; i < initialHolders.length; i++) {
            // Generate unique addresses
            address holder;
            assembly ("memory-safe") {
                mstore(0x00, add("FU holder", i))
                holder := keccak256(0x00, 0x20)
            }
            initialHolders[i] = holder;
        }
        initialHolders.quickSort();

        setChainId(1);

        deployFuDependencies();

        bytes32 fuSalt = 0x00000000000000000000000000000000000000000000000000000001a0dbafca;
        bytes32 buybackSalt = 0x0000000000000000000000000000000000000000000000000000000092858718;
        bytes memory fuInitcode = bytes.concat(
            type(FU).creationCode,
            abi.encode(bytes20(keccak256("git commit")), string("I am totally an SVG image, I promise"), initialHolders)
        );
        address fuPrediction = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deterministicDeployerFactory, fuSalt, keccak256(fuInitcode))
                    )
                )
            )
        );
        bytes memory buybackInitcode = bytes.concat(
            type(Buyback).creationCode,
            abi.encode(
                bytes20(keccak256("git commit")),
                address(uint160(uint256(keccak256("Buyback owner")))),
                5_000,
                fuPrediction
            )
        );
        address buybackPrediction = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), deterministicDeployerFactory, buybackSalt, keccak256(buybackInitcode)
                        )
                    )
                )
            )
        );

        if (
            uint160(address(pairFor(IERC20(fuPrediction), WETH))) / Settings.ADDRESS_DIVISOR != 1
                || uint160(buybackPrediction) / Settings.ADDRESS_DIVISOR != Settings.CRAZY_BALANCE_BASIS
        ) {
            console.log("You need to recompute the salt");
            console.log("Use the tool in `.../fu/mine`:");
            console.log(string.concat("The FU inithash is ", keccak256(fuInitcode).hexlify()));
            console.log("The truncated initcode for Buyback is:");
            assembly ("memory-safe") {
                mstore(buybackInitcode, sub(mload(buybackInitcode), 0x20))
            }
            console.logBytes(buybackInitcode);
            console.log("The number of leading zeroes is", Settings.PAIR_LEADING_ZEROES);
            revert();
        }

        // Deploy FU
        deal(address(this), 5 ether);
        deal(fuTxOrigin, 5 ether);
        setBaseFee(6 wei); // causes the `isSimulation` check to pass; Medusa is unable to prank `tx.origin`
        prank(fuTxOrigin);
        (bool success, bytes memory returndata) =
            deterministicDeployerFactory.call{value: 5 ether}(bytes.concat(fuSalt, fuInitcode));
        require(success);
        require(address(uint160(bytes20(returndata))) == fuPrediction);
        fu = IFU(fuPrediction);
        label(address(fu), "FU");

        // Lock initial liquidity
        IUniswapV2Pair pair = IUniswapV2Pair(fu.pair());
        label(address(pair), "FU/WETH UniV2 Pair");
        pair.mint(buybackPrediction);

        // Deploy buyback
        (success, returndata) = deterministicDeployerFactory.call(bytes.concat(buybackSalt, buybackInitcode));
        require(success);
        require(address(uint160(bytes20(returndata))) == buybackPrediction);
        buyback = Buyback(buybackPrediction);

        excludeContract(address(fu));
        excludeContract(address(pair));
        excludeContract(address(buyback));

        label(DEAD, "Super dead");
    }

    function setUp() external {
        (IFU fu,, address[] memory actors) = deployFu();
        guide = new FUGuide(fu, actors);
        warp(EPOCH);
    }

    function invariant_nonNegativeRebase() public virtual override {
        return guide.invariant_nonNegativeRebase();
    }

    function invariant_delegatesNotChanged() public virtual override {
        return guide.invariant_delegatesNotChanged();
    }

    function invariant_sumOfShares() public virtual override {
        return guide.invariant_sumOfShares();
    }

    function invariant_votingDelegation() public virtual override {
        return guide.invariant_votingDelegation();
    }

    function invariant_delegateeZero() public virtual override {
        return guide.invariant_delegateeZero();
    }

    function invariant_vacuous() external pure {}
}
