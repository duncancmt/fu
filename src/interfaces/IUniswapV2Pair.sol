// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

interface IUniswapV2Pair is IERC20 {
    function sync() external;
    function mint(address to) external returns (uint256);
}
