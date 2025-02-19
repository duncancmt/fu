// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC6372 {
    /// @notice Returns the current timepoint according to the mode the contract is operating on.
    /// @notice This is non-decreasing.
    function clock() external view returns (uint48);

    /// @notice Returns a machine-readable string description of the clock.
    // slither-disable-next-line naming-convention
    function CLOCK_MODE() external view returns (string memory);
}
