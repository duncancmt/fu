// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {INonces} from "./INonces.sol";

interface IERC2612 is IERC20, INonces {
    /// @notice Approves `spender` to spend `value` tokens on behalf of `owner` via an off-chain
    /// signature.
    /// @param owner The holder of the tokens and the signer of the EIP-712 object. Must not be the
    /// zero address.
    /// @param spender The account for which to create the allowance. `permit` causes `spender` to
    /// be able to move `owner`'s tokens.
    /// @param value The token amount of the allowance to be created.
    /// @param deadline The current blocktime must be less than or equal to `deadline`.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    // slither-disable-next-line naming-convention
    /// @notice Returns the EIP-712 domain separator used for signature verification.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
