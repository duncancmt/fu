// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

interface IERC7674 is IERC20 {
    function temporaryApprove(address spender, uint256 amount) external returns (bool);
}
