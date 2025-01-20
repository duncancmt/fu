// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FU} from "src/FU.sol";
import {Settings} from "src/core/Settings.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {QuickSort} from "script/QuickSort.sol";

import {Test} from "@forge-std/Test.sol";
import {Boilerplate} from "./Boilerplate.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
address constant TX_ORIGIN = 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6;
//address[] public actors;

contract FUTest is Boilerplate, Test {
    using QuickSort for address[];

    IUniswapV2Factory public FACTORY;
    FU public FUContract;

    function deployFu() internal {
        address[] memory initialHolders = new address[](Settings.ANTI_WHALE_DIVISOR * 2);
        for (uint i = 0; i < initialHolders.length; i++) {
            // Generate unique addresses
            address holder;
            assembly ("memory-safe") {
                mstore(0x00, add("FU holder", i))
                holder := keccak256(0x00, 0x20)
            }
            initialHolders[i] = holder;
        }
        initialHolders.quickSort();

        vm.prank(DEPLOYER, TX_ORIGIN);

        FUContract = new FU{value: 1 ether}(
            bytes20(keccak256("gitCommit")),
            "I am totally an SVG image, I promise",
            initialHolders
        );
    }

    function setUp() public virtual override {
        return deployFu();
    }
}
