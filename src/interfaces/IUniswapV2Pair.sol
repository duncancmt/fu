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
        }
    }
}

bytes32 constant INIT_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
