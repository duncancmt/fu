// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface INonces {
    function nonces(address account) external view returns (uint256 nonce);
}
