// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {INonces} from "./interfaces/INonces.sol";
import {IERC5805} from "./interfaces/IERC5805.sol";

import {Balance} from "./core/types/Balance.sol";
import {Shares} from "./core/types/Shares.sol";

import {CrazyBalance} from "./core/CrazyBalance.sol";
import {Checkpoints} from "./core/Checkpoints.sol";

abstract contract FUStorage is INonces, IERC5805 {
    mapping(address account => Shares shares) internal _sharesOf;
    Balance internal _totalSupply;
    Shares internal _totalShares;
    mapping(address owner => mapping(address spender => CrazyBalance allowed)) internal _allowance;
    mapping(address account => address delegatee) public override delegates;
    Checkpoints _checkpoints;
    mapping(address account => uint256 nonce) public override nonces;
}
