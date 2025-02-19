// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {INonces} from "./INonces.sol";
import {IERC6372} from "./IERC6372.sol";

interface IERC5805 is INonces, IERC6372 {
    /// @notice Returns the current voting weight of an account. 
    /// @notice This is the sum of the voting power delegated of each account delegating to it at
    /// this moment.
    function getVotes(address account) external view returns (uint256 votingWeight);

    /// @notice Returns the historical voting weight of an account. 
    /// @notice This is the sum of the voting power delegated of each account delegating to it at a
    /// specific timepoint. 
    /// @notice If this function does not revert, this is a constant value.
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256 votingWeight);

    /// @notice Returns the address to which the voting power of `account` is currently delegated.
    function delegates(address account) external view returns (address delegatee);

    /// @notice Changes the caller’s delegate, updating the vote delegation in the meantime.
    function delegate(address delegatee) external;

    /// @notice Changes an account's delegate using an off-chain signature, updating the vote
    /// delegation in the meantime.
    /// @param nonce Must be equal to the current value of `nonces(...)` for the signer.
    /// @param expiry The current blocktime must be less than or equal to `expiry`.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice Emitted when the delegate for an account is modified by `delegate` or
    /// `delegateBySig`.
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice Emitted when `delegate`'s available voting power changes from `previousBalance` to
    /// `newBalance`.
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}
