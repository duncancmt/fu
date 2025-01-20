// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC2612} from "./IERC2612.sol";

interface IUniswapV2Pair is IERC2612 {
    function sync() external;
    function mint(address to) external returns (uint256);
}

library FastUniswapV2PairLib {
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

    function fastMint(IUniswapV2Pair pair, address to) internal returns (uint256 r) {
        assembly ("memory-safe") {
            mstore(0x14, to)
            mstore(0x00, 0x6a627842000000000000000000000000)
            if iszero(call(gas(), pair, 0x00, 0x10, 0x24, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            r := mload(0x00)
        }
    }
}

bytes32 constant INIT_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
