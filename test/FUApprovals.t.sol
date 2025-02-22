// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FUDeploy, Common} from "./Deploy.t.sol";
import {Settings} from "../src/core/Settings.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {IERC7674} from "src/interfaces/IERC7674.sol";
import {IERC5805} from "src/interfaces/IERC5805.sol";

import {Test} from "@forge-std/Test.sol";
import {VmSafe} from "@forge-std/Vm.sol";
import {StdCheats} from "@forge-std/StdCheats.sol";

import {console} from "@forge-std/console.sol";

address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

function saturatingAdd(uint256 x, uint256 y) pure returns (uint256) {
    unchecked {
        if (x + y < x) {
            return type(uint256).max;
        }
    }
    return x + y;
}

function saturatingSub(uint256 x, uint256 y) pure returns (uint256) {
    if (y > x) {
        return 0;
    }
    return x - y;
}

contract TransientSlotLoader {
    fallback() external {
        assembly ("memory-safe") {
            mstore(0x00, tload(calldataload(0x00)))
            return(0x00, 0x20)
        }
    }
}

contract FUApprovalsTest is FUDeploy, Test {
    function setUp() public override {
        super.setUp();
        actors.push(pair);
        isActor[pair] = true;
    }

    function _tloadContraband(address target, bytes32 slot) private returns (bytes32 slotValue) {
        bytes memory code = target.code;
        vm.etch(target, type(TransientSlotLoader).runtimeCode); // TODO: Commmon.etch
        (bool success, bytes memory returndata) = target.staticcall(bytes.concat(slot));
        assertTrue(success);
        assertEq(returndata.length, 32);
        slotValue = bytes32(returndata);
        vm.etch(target, code);
    }

    function _smuggle(function (address, bytes32) internal returns (bytes32) f)
        private
        pure
        returns (function (address, bytes32) internal view returns (bytes32) r)
    {
        assembly ("memory-safe") {
            r := f
        }
    }

    function _tload(address target, bytes32 slot) internal view returns (bytes32) {
        return _smuggle(_tloadContraband)(target, slot);
    }

    function testTemporaryApprove(
        uint256 actorIndex,
        address spender,
        uint256 amount,
        bool boundSpender,
        bool boundAmount
    ) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, type(uint256).max);
        }
        console.log("amount", amount);
        console.log("spender", spender);

        if (boundSpender) {
            spender = getActor(spender);
        } else {
            maybeCreateActor(spender);
        }

        uint256 beforePersistentAllowance = uint256(
            load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        ); //allowance mapping offset is 8, see https://github.com/duncancmt/fu/blob/c64c7b7fbafd1ea362c056e4fecef44ed4ac5688/src/FUStorage.sol#L16-L26

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success,) = callOptionalReturn(abi.encodeCall(fu.temporaryApprove, (spender, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0, "temporaryApprove does not emit events");

        uint256 afterPersistentAllowance = uint256(
            load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        );

        if (spender == PERMIT2) {
            assertEq(beforePersistentAllowance, afterPersistentAllowance, "permit2 allowance should already be maximum");
        }
    }

    function _setupAllowances(
        address actor,
        address spender,
        uint256 amount,
        uint256 totalAllowance,
        uint256 persistentAllowance,
        uint256 transientAllowance,
        uint256 boundAllowance
    ) internal returns (uint256 beforePersistentAllowance, uint256 beforeTransientAllowance, uint256 beforeAllowance) {
        boundAllowance = bound(boundAllowance, 0, 4);
        if (boundAllowance >= 2) {
            totalAllowance = bound(totalAllowance, amount, type(uint256).max);
        }
        if (boundAllowance & 1 == 0) {
            persistentAllowance = bound(persistentAllowance, 0, totalAllowance);
            transientAllowance = bound(transientAllowance, 0, totalAllowance - persistentAllowance);
        } else {
            transientAllowance = bound(transientAllowance, 0, totalAllowance);
            persistentAllowance = bound(persistentAllowance, 0, totalAllowance - transientAllowance);
        }

        if (spender != PERMIT2) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Approval(actor, spender, persistentAllowance);
        }
        prank(actor);
        (bool success,) = callOptionalReturn(abi.encodeCall(IERC20.approve, (spender, persistentAllowance)));
        assertTrue(success);

        prank(actor);
        (success,) = callOptionalReturn(abi.encodeCall(IERC7674.temporaryApprove, (spender, transientAllowance)));
        assertTrue(success);

        beforePersistentAllowance = uint256(
            load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        );
        if (spender == PERMIT2) {
            assertEq(beforePersistentAllowance, 0, "PERMIT2 persistent allowance failed");
        } else {
            assertEq(beforePersistentAllowance, persistentAllowance, "setting persistent allowance failed");
        }
        beforeTransientAllowance = uint256(_tload(address(fu), keccak256(abi.encodePacked(actor, spender))));
        if (spender == PERMIT2) {
            assertEq(beforeTransientAllowance, 0, "PERMIT2 transient allowance failed");
        } else {
            assertEq(beforeTransientAllowance, transientAllowance, "setting transient allowance failed");
        }

        beforeAllowance = saturatingAdd(beforePersistentAllowance, beforeTransientAllowance);
        if (actor == pair) {
            beforeAllowance = 0;
        } else if (spender == PERMIT2) {
            beforeAllowance = type(uint256).max;
        }
    }

    function _checkAllowances(
        address actor,
        address spender,
        uint256 amount,
        uint256 beforePersistentAllowance,
        uint256 beforeTransientAllowance,
        uint256 beforeAllowance,
        bool expectedEvent
    ) internal returns (uint256 afterPersistentAllowance, uint256 afterTransientAllowance) {
        afterPersistentAllowance = uint256(
            load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        );
        afterTransientAllowance = uint256(_tload(address(fu), keccak256(abi.encodePacked(actor, spender))));

        if (spender == PERMIT2) {
            assertEq(afterPersistentAllowance, 0);
            assertEq(afterTransientAllowance, 0);
            assertEq(afterPersistentAllowance, beforePersistentAllowance);
            assertEq(afterTransientAllowance, beforeTransientAllowance);
            if (actor == pair) {
                assertEq(amount, 0);
            }
        } else if (actor == pair) {
            assertEq(amount, 0);
            assertEq(afterPersistentAllowance, beforePersistentAllowance);
            assertEq(afterTransientAllowance, 0);
        } else if (~beforeTransientAllowance == 0) {
            assertEq(afterPersistentAllowance, beforePersistentAllowance);
            assertEq(afterTransientAllowance, beforeTransientAllowance);
        } else if (~beforePersistentAllowance == 0) {
            assertEq(afterPersistentAllowance, beforePersistentAllowance);
            assertEq(afterTransientAllowance, saturatingSub(beforeTransientAllowance, amount));
        } else {
            assertEq(afterTransientAllowance, saturatingSub(beforeTransientAllowance, amount));
            if (beforeTransientAllowance < amount) {
                assertEq(afterPersistentAllowance, beforePersistentAllowance - (amount - beforeTransientAllowance));
            } else {
                assertEq(afterPersistentAllowance, beforePersistentAllowance);
            }
        }

        if (expectedEvent) {
            assertEq(
                (beforePersistentAllowance - afterPersistentAllowance)
                    + (beforeTransientAllowance - afterTransientAllowance),
                amount
            );
            assertEq(fu.allowance(actor, spender), saturatingAdd(afterPersistentAllowance, afterTransientAllowance));
        } else if (spender != PERMIT2) {
            if (afterTransientAllowance == 0) {
                if (actor != pair) {
                    assertEq(fu.allowance(actor, spender), afterPersistentAllowance);
                    if (beforeTransientAllowance != amount) {
                        assertEq(afterPersistentAllowance, type(uint256).max);
                    }
                }
            } else if (~beforeTransientAllowance != 0) {
                assertEq(afterTransientAllowance, beforeTransientAllowance - amount);
            }
        }
    }

    function _transferFromShouldFail(address from, address to, uint256 amount, uint256 balance, uint256 allowance)
        internal
        view
        returns (bool)
    {
        return from == DEAD || to == DEAD || to == address(fu) || to == from || amount > balance
            || uint160(to) / Settings.ADDRESS_DIVISOR == 0 || amount > allowance;
    }

    function testTransferFrom(
        address spender,
        uint256 actorIndex,
        address to,
        uint256 amount,
        uint256 totalAllowance,
        uint256 persistentAllowance,
        uint256 transientAllowance,
        bool boundTo,
        bool boundAmount,
        uint256 boundAllowance
    ) external {
        address actor = getActor(actorIndex);

        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        } else {
            console.log("amount", amount);
        }
        if (actor == pair) {
            assume(amount < fu.balanceOf(actor));
        }
        if (boundTo) {
            to = getActor(to);
        } else {
            maybeCreateActor(to);
        }

        (uint256 beforePersistentAllowance, uint256 beforeTransientAllowance, uint256 beforeAllowance) =
        _setupAllowances(
            actor, spender, amount, totalAllowance, persistentAllowance, transientAllowance, boundAllowance
        );
        assertEq(beforeAllowance, fu.allowance(actor, spender), "allowance mismatch");
        uint256 beforeBalance = fu.balanceOf(actor);

        bool expectedSuccess = !_transferFromShouldFail(actor, to, amount, beforeBalance, beforeAllowance);
        bool expectedEvent = expectedSuccess && spender != PERMIT2 && amount != 0 && beforeTransientAllowance < amount
            && ~beforePersistentAllowance != 0;

        if (expectedEvent) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Approval(actor, spender, beforePersistentAllowance - (amount - beforeTransientAllowance));
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(spender);

        (bool success, bytes memory returndata) =
            callOptionalReturn(abi.encodeCall(IERC20.transferFrom, (actor, to, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        assertEq(success, expectedSuccess, "unexpected failure");

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            return;
        }

        if (!expectedEvent) {
            for (uint256 i; i < logs.length; i++) {
                VmSafe.Log memory log = logs[i];
                assertNotEq(log.topics[0], IERC20.Approval.selector, "approve event");
            }
        }

        saveActor(actor);
        saveActor(to);

        _checkAllowances(
            actor, spender, amount, beforePersistentAllowance, beforeTransientAllowance, beforeAllowance, expectedEvent
        );
    }

    function _burnFromShouldFail(address from, uint256 amount, uint256 balance, uint256 allowance)
        internal
        view
        returns (bool)
    {
        return from == DEAD || amount > balance || amount > allowance;
    }

    function testBurnFrom(
        address spender,
        uint256 actorIndex,
        uint256 amount,
        uint256 totalAllowance,
        uint256 persistentAllowance,
        uint256 transientAllowance,
        bool boundAmount,
        uint256 boundAllowance
    ) external {
        address actor = getActor(actorIndex);

        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        } else {
            console.log("amount", amount);
        }

        (uint256 beforePersistentAllowance, uint256 beforeTransientAllowance, uint256 beforeAllowance) =
        _setupAllowances(
            actor, spender, amount, totalAllowance, persistentAllowance, transientAllowance, boundAllowance
        );
        assertEq(beforeAllowance, fu.allowance(actor, spender), "allowance mismatch");
        uint256 beforeBalance = fu.balanceOf(actor);

        bool expectedSuccess = !_burnFromShouldFail(actor, amount, beforeBalance, beforeAllowance);
        bool expectedEvent = expectedSuccess && spender != PERMIT2 && amount != 0 && beforeTransientAllowance < amount
            && ~beforePersistentAllowance != 0;

        if (expectedEvent) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Approval(actor, spender, beforePersistentAllowance - (amount - beforeTransientAllowance));
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(spender);

        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(IFU.burnFrom, (actor, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        assertEq(success, expectedSuccess, "unexpected failure");

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            return;
        }

        saveActor(actor);

        _checkAllowances(
            actor, spender, amount, beforePersistentAllowance, beforeTransientAllowance, beforeAllowance, expectedEvent
        );
    }

    function _deliverFromShouldFail(address from, uint256 amount, uint256 balance, uint256 allowance)
        internal
        view
        returns (bool)
    {
        return from == DEAD || amount > balance || amount > allowance;
    }

    function testDeliverFrom(
        address spender,
        uint256 actorIndex,
        uint256 amount,
        uint256 totalAllowance,
        uint256 persistentAllowance,
        uint256 transientAllowance,
        bool boundAmount,
        uint256 boundAllowance
    ) external {
        address actor = getActor(actorIndex);

        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        } else {
            console.log("amount", amount);
        }

        (uint256 beforePersistentAllowance, uint256 beforeTransientAllowance, uint256 beforeAllowance) =
        _setupAllowances(
            actor, spender, amount, totalAllowance, persistentAllowance, transientAllowance, boundAllowance
        );
        assertEq(beforeAllowance, fu.allowance(actor, spender), "allowance mismatch");
        uint256 beforeBalance = fu.balanceOf(actor);

        bool expectedSuccess = !_burnFromShouldFail(actor, amount, beforeBalance, beforeAllowance);
        bool expectedEvent = expectedSuccess && spender != PERMIT2 && amount != 0 && beforeTransientAllowance < amount
            && ~beforePersistentAllowance != 0;

        if (expectedEvent) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Approval(actor, spender, beforePersistentAllowance - (amount - beforeTransientAllowance));
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(spender);

        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(IFU.deliverFrom, (actor, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        assertEq(success, expectedSuccess, "unexpected failure");

        if (!success) {
            assert(
                keccak256(returndata)
                    != keccak256(hex"4e487b710000000000000000000000000000000000000000000000000000000000000001")
            );
            assertNoMutation(accountAccesses, logs);
            return;
        }

        saveActor(actor);

        _checkAllowances(
            actor, spender, amount, beforePersistentAllowance, beforeTransientAllowance, beforeAllowance, expectedEvent
        );
    }

    function testPermit(
        uint256 privKey,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        uint256 blockTimestamp,
        uint64 chainId,
        bool expired,
        bool fakeSig,
        bool badSig
    ) external {
        address owner;
        if (fakeSig) {
            //Convert private keys directly into addresses for fuzzing
            owner = address(uint160(bound(privKey, 0, type(uint160).max)));
        } else {
            privKey = boundPrivateKey(privKey);
            owner = vm.addr(privKey);
        }

        deadline = bound(deadline, getBlockTimestamp(), type(uint256).max);

        bytes32 nonceSlot = keccak256(abi.encode(owner, uint256(BASE_SLOT) + 10));
        store(address(fu), nonceSlot, bytes32(nonce));
        assertEq(fu.nonces(owner), nonce);
        if (expired) {
            if (~deadline == 0) {
                expired = false;
                blockTimestamp = getBlockTimestamp();
            } else {
                blockTimestamp = bound(blockTimestamp, deadline + 1, type(uint256).max);
            }
        } else {
            blockTimestamp = bound(blockTimestamp, getBlockTimestamp(), deadline);
        }
        warp(blockTimestamp);
        chainId = uint64(bound(chainId, 1, type(uint64).max - 1));
        vm.chainId(chainId);

        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256("Fuck You!"),
                chainId,
                fu
            )
        );
        assertEq(domainSep, fu.DOMAIN_SEPARATOR());
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 signingHash = keccak256(abi.encodePacked(hex"1901", domainSep, structHash));

        bool shouldFail = expired || owner == address(0) || badSig;

        uint8 v;
        bytes32 r;
        bytes32 s;
        if (fakeSig) {
            r = keccak256(abi.encodePacked("r", owner));
            s = keccak256(abi.encodePacked("s", owner));
            if (!shouldFail) {
                vm.mockCall(address(1), abi.encode(signingHash, v, r, s), abi.encode(owner));
                vm.expectCall(address(1), abi.encode(signingHash, v, r, s));
            }
        } else {
            (v, r, s) = vm.sign(privKey, signingHash);
        }

        if (owner == address(0)) {
            vm.expectRevert(abi.encodeWithSignature("ERC20InvalidApprover(address)", owner));
        } else if (expired) {
            vm.expectRevert(abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", deadline));
        } else if (badSig) {
            r = keccak256(bytes.concat(r));
            s = keccak256(bytes.concat(s));
            vm.expectRevert(abi.encodeWithSignature("ERC2612InvalidSigner(address,address)", ecrecover(signingHash, v, r, s), owner));
        }

        fu.permit(owner, spender, value, deadline, v, r, s);

        if (!shouldFail) {
            uint256 newNonce = uint256(load(address(fu), nonceSlot));
            unchecked {
                assertEq(newNonce, nonce + 1);
                assertEq(fu.nonces(owner), nonce + 1);
            }
            uint256 newAllowance = uint256(
                load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(owner, uint256(BASE_SLOT) + 8)))))
            );
            if (spender == PERMIT2) {
                assertEq(newAllowance, 0);
                if (owner == pair) {
                    assertEq(fu.allowance(owner, spender), 0);
                } else {
                    assertEq(fu.allowance(owner, spender), type(uint256).max);
                }
            } else {
                assertEq(newAllowance, value);
                if (owner == pair) {
                    assertEq(fu.allowance(owner, spender), 0);
                } else {
                    assertEq(fu.allowance(owner, spender), value);
                }
            }
        }
    }

    function testDelegateBySig(
        uint256 privKey,
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint256 blockTimestamp,
        uint64 chainId,
        bool expired,
        bool fakeSig,
        bool badSig
    ) external {
        address delegator;
        if (fakeSig) {
            //Convert private keys directly into addresses for fuzzing
            delegator = address(uint160(bound(privKey, 0, type(uint160).max)));
        } else {
            privKey = boundPrivateKey(privKey);
            delegator = vm.addr(privKey);
        }

        expiry = bound(expiry, getBlockTimestamp(), type(uint256).max);

        bytes32 nonceSlot = keccak256(abi.encode(delegator, uint256(BASE_SLOT) + 10));
        store(address(fu), nonceSlot, bytes32(nonce));
        if (expired) {
            if (~expiry == 0) {
                expired = false;
                blockTimestamp = getBlockTimestamp();
            } else {
                blockTimestamp = bound(blockTimestamp, expiry + 1, type(uint256).max);
            }
        } else {
            blockTimestamp = bound(blockTimestamp, getBlockTimestamp(), expiry);
        }
        warp(blockTimestamp);
        chainId = uint64(bound(chainId, 1, type(uint64).max - 1));
        vm.chainId(chainId);

        bytes32 domainSep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256("Fuck You!"),
                chainId,
                fu
            )
        );
        assertEq(domainSep, fu.DOMAIN_SEPARATOR());
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"),
                delegatee,
                nonce,
                expiry
            )
        );
        bytes32 signingHash = keccak256(abi.encodePacked(hex"1901", domainSep, structHash));

        bool shouldFail = expired || delegator == address(0) || badSig;

        uint8 v;
        bytes32 r;
        bytes32 s;
        if (fakeSig) {
            r = keccak256(abi.encodePacked("r", delegator));
            s = keccak256(abi.encodePacked("s", delegator));
            if (!shouldFail) {
                vm.mockCall(address(1), abi.encode(signingHash, v, r, s), abi.encode(delegator));
                vm.expectCall(address(1), abi.encode(signingHash, v, r, s));
            }
        } else {
            (v, r, s) = vm.sign(privKey, signingHash);
        }

        if (expired) {
            vm.expectRevert(abi.encodeWithSignature("ERC5805ExpiredSignature(uint256)", expiry));
        } else if (delegator == address(0)) {
            vm.expectRevert(abi.encodeWithSignature("ERC5805InvalidSignature()"));
        } else if (badSig) {
            r = keccak256(bytes.concat(r));
            s = keccak256(bytes.concat(s));
            address actualSigner = ecrecover(signingHash, v, r, s);
            if (actualSigner == address(0)) {
                vm.expectRevert(abi.encodeWithSignature("ERC5805InvalidSignature()"));
            } else {
                vm.expectRevert(abi.encodeWithSignature("ERC5805InvalidNonce(uint256,uint256)", nonce, 0));
            }
        } else {
            expectEmit(true, true, true, true, address(fu));
            emit IERC5805.DelegateChanged(delegator, address(0), delegatee);
        }

        fu.delegateBySig(delegatee, nonce, expiry, v, r, s);

        if (!shouldFail) {
            uint256 newNonce = uint256(load(address(fu), nonceSlot));
            unchecked {
                assertEq(newNonce, nonce + 1);
            }
            bytes32 newDelegatee = load(address(fu), keccak256(abi.encode(delegator, uint256(BASE_SLOT) + 9)));
            assertEq(uint256(uint160(delegatee)), uint256(newDelegatee), "Delegatee addresses don't match");
        }
    }

    // Solidity inheritance is dumb
    function deal(address who, uint256 value) internal virtual override(Common, StdCheats) {
        return super.deal(who, value);
    }
}
