// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "@forge-std/Script.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import {QuickSort} from "./QuickSort.sol";

interface IMulticall {
    /// @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
    ///                     operation has to be uint8(0) in this version (=> 1 byte),
    ///                     to as a address (=> 20 bytes),
    ///                     value as a uint256 (=> 32 bytes),
    ///                     data length as a uint256 (=> 32 bytes),
    ///                     data as bytes.
    function multiSend(bytes memory transactions) external payable;
}

contract FundBurners is Script {
    using QuickSort for address[];
    using stdJson for string;

    IMulticall internal constant _MULTICALL = IMulticall(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);
    address internal constant _DEPLOYER_BROADCASTER = 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6;

    function run() external {
        address[] memory burners =
            abi.decode(vm.readFile(string.concat(vm.projectRoot(), "/burners.json")).parseRaw("$"), (address[]));
        burners.quickSort();

        bytes memory payload;
        assembly ("memory-safe") {
            payload := mload(0x40)
            mstore(payload, mul(0x55, mload(burners)))
            mstore(0x40, add(0x20, add(payload, mload(payload))))
            for {
                let src := add(0x20, burners)
                let end := add(shl(0x05, mload(burners)), src)
                let dst := add(0x20, payload)
            } lt(src, end) {
                src := add(0x20, src)
                dst := add(0x55, dst)
            } {
                mstore8(dst, 0x00)
                mstore(add(0x01, dst), shl(0x60, mload(src)))
                mstore(add(0x15, dst), 0x2386f26fc10000)
                mstore(add(0x35, dst), 0x00)
            }
        }

        uint256 totalValue = 0.01 ether * burners.length;
        vm.startBroadcast(_DEPLOYER_BROADCASTER);
        _MULTICALL.multiSend{value: totalValue}(payload);
        vm.stopBroadcast();
    }
}
