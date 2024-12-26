// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {FU} from "src/FU.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {pairFor} from "src/interfaces/IUniswapV2Factory.sol";

import {Math} from "./Math.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import {Script} from "@forge-std/Script.sol";
import {VmSafe} from "@forge-std/Vm.sol";

import {console} from "@forge-std/console.sol";

interface IMulticall {
    /// @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
    ///                     operation has to be uint8(0) in this version (=> 1 byte),
    ///                     to as a address (=> 20 bytes),
    ///                     value as a uint256 (=> 32 bytes),
    ///                     data length as a uint256 (=> 32 bytes),
    ///                     data as bytes.
    function multiSend(bytes memory transactions) external payable;
}

contract DeployFU is Script {
    using stdJson for string;

    address internal constant _DEPLOYER_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    IMulticall internal constant _MULTICALL = IMulticall(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);
    address internal constant _DEPLOYER_BROADCASTER = 0xD6B66609E5C05210BE0A690aB3b9788BA97aFa60;
    IERC20 internal constant _WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function run(uint256 value, bytes32 salt, string memory image) external {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/airdrop.json"));
        address[] memory initialHolders = abi.decode(json.parseRaw("$"), (address[]));

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

        bytes memory initcode = bytes.concat(type(FU).creationCode, abi.encode(gitCommit, image, initialHolders));
        IERC20 fu = IERC20(
            address(
                uint160(
                    uint256(keccak256(abi.encodePacked(bytes1(0xff), _DEPLOYER_PROXY, salt, keccak256(initcode))))
                )
            )
        );
        IUniswapV2Pair pair = pairFor(fu, _WETH);
        bytes memory mint = abi.encodeCall(pair.mint, (address(0)));

        bytes memory calls = abi.encodePacked(
            uint8(0),
            _DEPLOYER_PROXY,
            value,
            initcode.length + 32,
            bytes.concat(salt, initcode),
            uint8(0),
            pair,
            uint256(0),
            mint.length,
            mint
        );

        vm.startBroadcast(_DEPLOYER_BROADCASTER);
        _MULTICALL.multiSend{value: value}(calls);
        vm.stopBroadcast();

        uint256 wethBalance = _WETH.balanceOf(address(pair));
        uint256 fuBalance = fu.balanceOf(address(pair));
        uint256 liquidity = Math.sqrt(fuBalance * wethBalance);
        require(pair.balanceOf(address(0)) == liquidity);
    }
}
