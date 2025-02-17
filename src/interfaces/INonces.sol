// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface INonces {
    /// @notice Returns the current nonce for `account` to be used for off-chain signatures.
    function nonces(address account) external view returns (uint256 nonce);
}
