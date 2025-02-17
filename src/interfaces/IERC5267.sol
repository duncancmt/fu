// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC5267 {
    /// @notice Returns the un-hashed fields that comprise the EIP-712 domain.
    /// @return fields A bitmask indicating which domain fields are used.
    /// @return name The human-readable name of the domain.
    /// @return chainId The chain ID of the network.
    /// @return verifyingContract The address of this contract.
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
}
