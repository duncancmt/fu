// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC2612} from "./IERC2612.sol";

interface IUniswapV2Pair is IERC2612 {
    function sync() external;
    function mint(address to) external returns (uint256);
}

bytes32 constant INIT_HASH = 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
