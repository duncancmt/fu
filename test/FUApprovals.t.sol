// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FUDeploy, Common} from "./Deploy.t.sol";
import {Settings} from "../src/core/Settings.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {IERC7674} from "src/interfaces/IERC7674.sol";

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

    function _smuggle(function (address, bytes32) internal returns (bytes32) f) private pure returns (function (address, bytes32) internal view returns (bytes32) r) {
        assembly ("memory-safe") {
            r := f
        }
    }

    function _tload(address target, bytes32 slot) internal view returns (bytes32) {
        return _smuggle(_tloadContraband)(target, slot);
    }

    function _transferFromShouldFail(address from, address to, uint256 amount, uint256 balance, uint256 allowance)
        internal
        view
        returns (bool)
    {
        return from == DEAD || to == DEAD || to == address(fu) || to == from || amount > balance
            || uint160(to) / Settings.ADDRESS_DIVISOR == 0 || amount > allowance;
    }

    function testTemporaryApprove(uint256 actorIndex, address spender, uint256 amount, bool boundSpender, bool boundAmount) external {
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
            vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        ); //allowance mapping offset is 8, see https://github.com/duncancmt/fu/blob/c64c7b7fbafd1ea362c056e4fecef44ed4ac5688/src/FUStorage.sol#L16-L26

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success,) = callOptionalReturn(abi.encodeCall(fu.temporaryApprove, (spender, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 0, "temporaryApprove does not emit events");

        uint256 afterPersistentAllowance = uint256(
            vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))
        );

        if (spender == PERMIT2) {
            assertEq(beforePersistentAllowance, afterPersistentAllowance, "permit2 allowance should already be maximum");
        }
    }

    function testTransferFrom(address spender, uint256 actorIndex, address to, uint256 amount, uint256 totalAllowance, uint256 persistentAllowance, uint256 transientAllowance, bool boundTo, bool boundAmount, uint256 boundAllowance) external {
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

        prank(actor);
        (bool success,) = callOptionalReturn(abi.encodeCall(IERC20.approve, (spender, persistentAllowance)));
        assertTrue(success);

        prank(actor);
        (success,) = callOptionalReturn(abi.encodeCall(IERC7674.temporaryApprove, (spender, transientAllowance)));
        assertTrue(success);

        uint256 beforePersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        if (spender == PERMIT2) {
            assertEq(beforePersistentAllowance, 0, "PERMIT2 persistent allowance failed");
        } else {
            assertEq(beforePersistentAllowance, persistentAllowance, "setting persistent allowance failed");
        }
        uint256 beforeTransientAllowance = uint256(_tload(address(fu), keccak256(abi.encodePacked(actor, spender))));
        if (spender == PERMIT2) {
            assertEq(beforeTransientAllowance, 0, "PERMIT2 transient allowance failed");
        } else {
            assertEq(beforeTransientAllowance, transientAllowance, "setting transient allowance failed");
        }

        uint256 beforeAllowance = saturatingAdd(beforePersistentAllowance, beforeTransientAllowance);
        if (actor == pair) {
            beforeAllowance = 0;
        } else if (spender == PERMIT2) {
            beforeAllowance = type(uint256).max;
        }
        assertEq(beforeAllowance, fu.allowance(actor, spender), "allowance mismatch");
        uint256 beforeBalance = fu.balanceOf(actor);

        bool expectedSuccess = !_transferFromShouldFail(actor, to, amount, beforeBalance, beforeAllowance);
        bool expectedEvent = expectedSuccess && spender != PERMIT2 && amount != 0 && beforeTransientAllowance < amount && ~beforePersistentAllowance != 0;

        if (expectedEvent) {
            expectEmit(true, true, true, true, address(fu));
            emit IERC20.Approval(actor, spender, beforePersistentAllowance - (amount - beforeTransientAllowance));
        }

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(spender);

        bytes memory returndata;
        (success, returndata) = callOptionalReturn(abi.encodeCall(IERC20.transferFrom, (actor, to, amount)));

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

        uint256 afterPersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        uint256 afterTransientAllowance = uint256(_tload(address(fu), keccak256(abi.encodePacked(actor, spender))));

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
            assertEq((beforePersistentAllowance - afterPersistentAllowance) + (beforeTransientAllowance - afterTransientAllowance), amount);
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

    function testBurnFrom(address spender, uint256 actorIndex, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);

        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        } else {
            console.log("amount", amount);
        }
        if (actor == pair) {
            assume(amount < fu.balanceOf(actor));
        }

        uint256 beforePersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        console.log("beforePersistentAllowance:", beforePersistentAllowance);
        uint256 beforeBalance = fu.balanceOf(actor);

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(IFU.burnFrom, (actor, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256 afterPersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        uint256 afterBalance = fu.balanceOf(actor);

        assertEq((beforeBalance - afterBalance), (beforePersistentAllowance - afterPersistentAllowance), "change in balances and allowances don't match");
    }

    function testDeliverFrom(address spender, uint256 actorIndex, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);

        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        } else {
            console.log("amount", amount);
        }
        if (actor == pair) {
            assume(amount < fu.balanceOf(actor));
        }

        uint256 beforePersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        uint256 beforeBalance = fu.balanceOf(actor);

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success,) = callOptionalReturn(abi.encodeCall(IFU.deliverFrom, (actor, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256 afterPersistentAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));
        uint256 afterBalance = fu.balanceOf(actor);

        assertEq((beforeBalance - afterBalance), (beforePersistentAllowance - afterPersistentAllowance), "change in balances and allowances don't match");
    }

    // Solidity inheritance is dumb
    function deal(address who, uint256 value) internal virtual override(Common, StdCheats) {
        return super.deal(who, value);
    }
}
