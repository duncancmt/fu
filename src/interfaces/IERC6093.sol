// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC6093 {
    /// @notice Indicates an error related to the current `balance` of a `sender`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice Indicates a failure with the token `sender`.
    error ERC20InvalidSender(address sender);

    /// @notice Indicates a failure with the token `receiver`.
    error ERC20InvalidReceiver(address receiver);

    /// @notice Indicates a failure with the `spender`’s `allowance`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice Indicates a failure with the `approver` of a token to be approved.
    error ERC20InvalidApprover(address approver);

    /// @notice Indicates that the `deadline` of the `permit` has passed.
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @notice Indicates a mismatch between the `owner` of a permit and the signer of the EIP-712
    /// object.
    error ERC2612InvalidSigner(address signer, address owner);

    /// @notice Indicates that the `expiry` of the `delegateBySig` has passed.
    error ERC5805ExpiredSignature(uint256 expiry);

    /// @notice Indicates that the signature of the `delegateBySig` is malformed.
    error ERC5805InvalidSignature();

    /// @notice Indicates that the current `nonces(...)` of the signer does not match the given
    /// `nonce` value.
    error ERC5805InvalidNonce(uint256 actual, uint256 expected);

    /// @notice Indicates that the queried `timepoint` is equal to or greater than the current value
    /// `clock`.
    error ERC5805TimepointNotPast(uint256 timepoint, uint256 clock);
}
