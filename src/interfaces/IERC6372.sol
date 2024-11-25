// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC6372 {
    function clock() external view returns (uint48);
    // slither-disable-next-line naming-convention
    function CLOCK_MODE() external view returns (string memory);
}
