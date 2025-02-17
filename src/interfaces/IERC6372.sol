// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC6372 {
    /// @notice Returns the current timepoint according to the mode the contract is operating on.
    /// @notice This is non-decreasing.
    function clock() external view returns (uint48);
    // slither-disable-next-line naming-convention
    /// @notice Returns a machine-readable string description of the clock.
    function CLOCK_MODE() external view returns (string memory);
}
