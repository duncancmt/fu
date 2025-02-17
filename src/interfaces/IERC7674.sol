// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

interface IERC7674 is IERC20 {
    /// @notice Allows `spender` to withdraw *within the same transaction*, from the caller,
    /// multiple times, up to `amount`.
    function temporaryApprove(address spender, uint256 amount) external returns (bool);
}
