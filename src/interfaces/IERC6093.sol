// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC6093 {
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);

    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    error ERC5805ExpiredSignature(uint256 expiry);
    error ERC5805InvalidSignature();
    error ERC5805InvalidNonce(uint256 actual, uint256 expected);
}
