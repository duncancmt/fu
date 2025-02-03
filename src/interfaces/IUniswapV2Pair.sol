// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC2612} from "./IERC2612.sol";

interface IUniswapV2Pair is IERC2612 {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

library FastUniswapV2PairLib {
    function fastGetReserves(IUniswapV2Pair pair)
        internal
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)

            mstore(0x00, 0x0902f1ac)

            if iszero(staticcall(gas(), pair, 0x1c, 0x04, 0x00, 0x60)) {
                let ptr_ := mload(0x40)
                returndatacopy(ptr_, 0x00, returndatasize())
                revert(ptr_, returndatasize())
            }

            reserve0 := mload(0x00)
            reserve1 := mload(0x20)
            blockTimestampLast := mload(0x40)

            mstore(0x40, ptr)
        }
    }

    function fastBurn(IUniswapV2Pair pair, address to) internal returns (uint256 amount0, uint256 amount1) {
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

    function fastSwap(IUniswapV2Pair pair, uint256 amount0, uint256 amount1, address to) internal {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, 0x022c0d9f) // selector for `swap(uint256,uint256,address,bytes)`
            mstore(add(0x20, ptr), amount0)
            mstore(add(0x40, ptr), amount1)
            mstore(add(0x60, ptr), and(0xffffffffffffffffffffffffffffffffffffffff, to))
            mstore(add(0x80, ptr), 0x80)
            mstore(add(0xa0, ptr), 0x00)

            if iszero(call(gas(), pair, 0x00, add(0x1c, ptr), 0xa4, 0x00, 0x00)) {
                let ptr_ := mload(0x40)
                returndatacopy(ptr_, 0x00, returndatasize())
                revert(ptr_, returndatasize())
            }
        }
    }
}

bytes32 constant INIT_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
