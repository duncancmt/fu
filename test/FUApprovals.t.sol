// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FUDeploy, Common} from "./Deploy.t.sol";

import {Test} from "@forge-std/Test.sol";
import {VmSafe} from "@forge-std/Vm.sol";
import {StdCheats} from "@forge-std/StdCheats.sol";

import {console} from "@forge-std/console.sol";

contract FUApprovalsTest is FUDeploy, Test {
    function testTemporaryApprove(uint256 actorIndex, address spender, uint256 amount, bool boundSpender, bool boundAmount) external returns (bool) {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, type(uint256).max);
        }
        console.log("amount", amount);

        if (boundSpender) {
            spender = getActor(spender);
        } else {
            maybeCreateActor(spender);
        }

        uint256 beforeAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8)))))); //allowance mapping offset is 8, see https://github.com/duncancmt/fu/blob/c64c7b7fbafd1ea362c056e4fecef44ed4ac5688/src/FUStorage.sol#L16-L26

        vm.recordLogs();
        vm.startStateDiffRecording();
        prank(actor);

        (bool success,) = callOptionalReturn(abi.encodeCall(fu.temporaryApprove, (spender, amount)));

        VmSafe.AccountAccess[] memory accountAccesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        uint256 afterAllowance = uint256(vm.load(address(fu), keccak256(abi.encode(spender, keccak256(abi.encode(actor, uint256(BASE_SLOT) + 8))))));

        if (spender == PERMIT2) {
            assertEq(beforeAllowance, afterAllowance, "permit2 allowance should already be maximum");
        }
    }

    // Solidity inheritance is dumb
    function deal(address who, uint256 value) internal virtual override(Common, StdCheats) {
        return super.deal(who, value);
    }
}
