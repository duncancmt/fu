// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IUniswapV2Pair, INIT_HASH} from "./IUniswapV2Pair.sol";

interface IUniswapV2Factory {
    function createPair(IERC20 tokenA, IERC20 tokenB) external returns (IUniswapV2Pair pair);
    function getPair(IERC20 tokenA, IERC20 tokenB) external view returns (IUniswapV2Pair pair);
    function feeTo() external view returns (address);
}

library FastUniswapV2FactoryLib {
    function fastFeeTo(IUniswapV2Factory factory) internal view returns (address r) {
        assembly ("memory-safe") {
            mstore(0x00, 0x017e7e58) // selector for `feeTo()`

            if iszero(staticcall(gas(), factory, 0x1c, 0x04, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }

            r := mload(0x00)
            if shr(0xa0, r) { revert(0x00, 0x00) }
        }
    }
}

IUniswapV2Factory constant FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

function pairFor(IERC20 tokenA, IERC20 tokenB) pure returns (IUniswapV2Pair) {
    (tokenA, tokenB) = tokenB < tokenA ? (tokenB, tokenA) : (tokenA, tokenB);
    bytes32 salt = keccak256(abi.encodePacked(tokenA, tokenB));
    bytes32 result = keccak256(abi.encodePacked(bytes1(0xff), FACTORY, salt, INIT_HASH));
    return IUniswapV2Pair(address(uint160(uint256(result))));
}
