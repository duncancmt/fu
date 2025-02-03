// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC2612} from "./IERC2612.sol";

interface IUniswapV2Pair is IERC2612 {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve0, uint32 blockTimestampLast);

    function sync() external;
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

library FastUniswapV2PairLib {
    function fastGetReserves(IUniswapV2Pair) internal view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(0x00, 0x0902f1ac)

            if iszero(staticcall(gas(), pair, 0x1c, 0x04, 0x00, 0x60)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }

            reserve0 := mload(0x00)
            reserve1 := mload(0x20)
            blockTimestampLast := mload(0x40)

            mstore(0x40, ptr)
        }
    }

    function fastSync(IUniswapV2Pair pair) internal {
        assembly ("memory-safe") {
            mstore(0x00, 0xfff6cae9) // Selector for `sync()`

            if iszero(call(gas(), pair, 0x00, 0x1c, 0x04, 0x00, 0x00)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We do not bother to check that `pair` has code (vacuous success). We assume that it
            // does have code and that failure is signaled by reverting.
        }
    }

    function fastMint(IUniswapV2Pair pair, address to) internal returns (uint256 liquidity) {
        assembly ("memory-safe") {
            mstore(0x14, to)
            mstore(0x00, 0x6a627842000000000000000000000000) // selector for `mint(address)` with `to`'s padding
            if iszero(call(gas(), pair, 0x00, 0x10, 0x24, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            liquidity := mload(0x00)
        }
    }

    function fastMint(IUniswapV2Pair pair, address to) internal returns (uint256 amount0, uint256 amount1) {
        assembly ("memory-safe") {
            mstore(0x14, to)
            mstore(0x00, 0x89afcb44000000000000000000000000) // selector for `burn(address)` with `to`'s padding
            if iszero(call(gas(), pair, 0x00, 0x10, 0x24, 0x00, 0x40)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            amount0 := mload(0x00)
            amount1 := mload(0x20)
        }
    }
}

bytes32 constant INIT_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
