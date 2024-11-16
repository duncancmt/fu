// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

interface IUniswapV2Factory {
    function createPair(IERC20 tokenA, IERC20 tokenB) external returns (IUniswapV2Pair pair);
    function getPair(IERC20 tokenA, IERC20 tokenB) external view returns (IUniswapV2Pair pair);
}

IUniswapV2Factory constant FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
