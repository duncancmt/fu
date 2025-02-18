// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {pairFor} from "src/interfaces/IUniswapV2Factory.sol";

import {IPFS} from "src/lib/IPFS.sol";
import {Math} from "src/lib/Math.sol";
import {ItoA} from "src/lib/ItoA.sol";
import {Hexlify} from "./Hexlify.sol";
import {QuickSort} from "./QuickSort.sol";
import {stdJson} from "@forge-std/StdJson.sol";

import {FU} from "src/FU.sol";
import {Settings} from "src/core/Settings.sol";
import {Buyback} from "src/Buyback.sol";

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
    using ItoA for uint256;
    using Hexlify for bytes32;
    using QuickSort for address[];
    using stdJson for string;

    address internal constant _DEPLOYER_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    IMulticall internal constant _MULTICALL = IMulticall(0x40A2aCCbd92BCA938b02010E17A5b8929b49130D);
    address internal constant _DEPLOYER_BROADCASTER = 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6;
    IERC20 internal constant _WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint256 internal constant _MINIMUM_LIQUIDITY = 1000;

    function run(bytes32 fuSalt, bytes32 buybackSalt) external {
        address[] memory initialHolders =
            abi.decode(vm.readFile(string.concat(vm.projectRoot(), "/airdrop.json")).parseRaw("$"), (address[]));
        initialHolders.quickSort();
        string memory image = vm.readFile(string.concat(vm.projectRoot(), "/image.svg"));
        string memory imageUri = IPFS.CIDv0(IPFS.dagPbUnixFsHash(image));
        console.log("image URI", imageUri);
        assert(keccak256(bytes(imageUri)) == keccak256("ipfs://QmWH4FgvCpXdaZZ9zj5Zn2jvNYMgsLJ9YdG7YWD72p6wmP"));

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

        bytes memory fuInitcode = bytes.concat(type(FU).creationCode, abi.encode(gitCommit, image, initialHolders));
        FU fu = FU(
            address(
                uint160(
                    uint256(keccak256(abi.encodePacked(bytes1(0xff), _DEPLOYER_PROXY, fuSalt, keccak256(fuInitcode))))
                )
            )
        );
        IUniswapV2Pair pair = pairFor(fu, _WETH);
        bytes memory buybackInitcode = bytes.concat(
            type(Buyback).creationCode, abi.encode(gitCommit, 0xD6B66609E5C05210BE0A690aB3b9788BA97aFa60, 5_000, fu)
        );
        Buyback buyback = Buyback(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(bytes1(0xff), _DEPLOYER_PROXY, buybackSalt, keccak256(buybackInitcode))
                        )
                    )
                )
            )
        );

        if (
            uint160(address(pair)) / Settings.ADDRESS_DIVISOR != 1
                && uint160(address(buyback)) / Settings.ADDRESS_DIVISOR != Settings.CRAZY_BALANCE_BASIS
                && fuSalt == bytes32(0) && buybackSalt == bytes32(0)
        ) {
            console.log("Use the tool in `.../fu/mine` to compute the salt:");
            console.log(
                string.concat(
                    "\tcargo run --release ",
                    keccak256(fuInitcode).hexlify(),
                    " <BUYBACK_INITCODE_PREFIX> ",
                    Settings.PAIR_LEADING_ZEROES.itoa()
                )
            );
            console.log("\tBuyback initcode prefix:");
            assembly ("memory-safe") {
                mstore(buybackInitcode, sub(mload(buybackInitcode), 0x20))
            }
            console.logBytes(buybackInitcode);
            return;
        }

        bytes memory mint = abi.encodeCall(pair.mint, (address(buyback)));

        bytes memory calls = abi.encodePacked(
            uint8(0),
            _DEPLOYER_PROXY,
            uint256(5 ether),
            fuInitcode.length + 32,
            bytes.concat(fuSalt, fuInitcode),
            uint8(0),
            pair,
            uint256(0),
            mint.length,
            mint,
            uint8(0),
            _DEPLOYER_PROXY,
            uint256(0),
            buybackInitcode.length + 32,
            bytes.concat(buybackSalt, buybackInitcode)
        );

        vm.startBroadcast(_DEPLOYER_BROADCASTER);
        _MULTICALL.multiSend{value: 5 ether}(calls);
        vm.stopBroadcast();

        uint256 wethBalance = _WETH.balanceOf(address(pair));
        uint256 fuBalance = fu.balanceOf(address(pair));
        uint256 liquidity = Math.sqrt(fuBalance * wethBalance) - _MINIMUM_LIQUIDITY;
        require(pair.balanceOf(address(buyback)) == liquidity);
        require(pair.balanceOf(address(0)) == _MINIMUM_LIQUIDITY);
        assert(address(buyback).code.length != 0);
        assert(keccak256(bytes(fu.image())) == keccak256(bytes(imageUri)));
        assert(keccak256(bytes(fu.tokenURI())) == keccak256("ipfs://QmYFBfLpRNdTHFEmLNt26xCF7zkeSkJ5Nv7UZ4djFKDMWR"));
    }
}
