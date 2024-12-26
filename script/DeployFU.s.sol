// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FU} from "src/FU.sol";

import {stdJson} from "@forge-std/StdJson.sol";
import {ItoA} from "./ItoA.sol";

import {Script} from "@forge-std/Script.sol";
import {VmSafe} from "@forge-std/Vm.sol";

contract DeployFU is Script {
    using stdJson for string;
    using ItoA for uint256;

    address internal constant _DEPLOYER_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant _DEPLOYER_BROADCASTER = 0xD6B66609E5C05210BE0A690aB3b9788BA97aFa60;

    function _getAirdropRecipient(string memory json, uint256 i) private pure returns (address r) {
        uint256 freePtr;
        assembly ("memory-safe") {
            freePtr := mload(0x40)
        }

        r = abi.decode(json.parseRaw(string.concat(".[", i.itoa(), "]")), (address));

        assembly ("memory-safe") {
            mstore(0x40, freePtr)
        }
    }

    function run(uint256 value, bytes32 salt, string memory image) external {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/airdrop.json"));
        uint256 length = abi.decode(json.parseRaw("length"), (uint256));
        address[] memory initialHolders = new address[](length);
        for (uint256 i; i < length; i++) {
            initialHolders[i] = _getAirdropRecipient(json, i);
        }

        bytes20 gitCommit;
        {
            string[] memory gitCommand = new string[](3);
            gitCommand[0] = "git";
            gitCommand[1] = "rev-parse";
            gitCommand[2] = "HEAD";
            VmSafe.FfiResult memory result = vm.tryFfi(gitCommand);
            assert(result.exitCode == 0);
            assert(result.stderr.length == 0);
            assert(result.stdout.length == 20);
            gitCommit = bytes20(result.stdout);
        }

        assert(value < _DEPLOYER_BROADCASTER.balance);

        vm.startBroadcast(_DEPLOYER_BROADCASTER);
        (bool success, bytes memory data) = _DEPLOYER_PROXY.call(
            bytes.concat(salt, type(FU).creationCode, abi.encode(gitCommit, image, initialHolders))
        );
        vm.stopBroadcast();

        if (!success) {
            assembly ("memory-safe") {
                revert(add(0x20, data), mload(data))
            }
        }
    }
}
