// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IUniswapV2Pair, INIT_HASH} from "./IUniswapV2Pair.sol";

interface IUniswapV2Factory {
    function createPair(IERC20 tokenA, IERC20 tokenB) external returns (IUniswapV2Pair pair);
    function getPair(IERC20 tokenA, IERC20 tokenB) external view returns (IUniswapV2Pair pair);
}

IUniswapV2Factory constant FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

function pairFor(IERC20 tokenA, IERC20 tokenB) pure returns (IUniswapV2Pair) {
    (tokenA, tokenB) = tokenB < tokenA ? (tokenB, tokenA) : (tokenA, tokenB);
    bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
    bytes32 result = keccak256(abi.encodePacked(bytes1(0xff), FACTORY, salt, INIT_HASH));
    return IUniswapV2Pair(address(uint160(uint256(result))));
}
