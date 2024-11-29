// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {INonces} from "./INonces.sol";

interface IERC2612 is IERC20, INonces {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
