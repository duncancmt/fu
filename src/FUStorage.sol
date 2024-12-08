// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {INonces} from "./interfaces/INonces.sol";
import {IERC5805} from "./interfaces/IERC5805.sol";

import {Tokens} from "./types/Tokens.sol";
import {Shares} from "./types/Shares.sol";
import {CrazyBalance} from "./types/CrazyBalance.sol";

import {Checkpoints} from "./core/Checkpoints.sol";
import {RebaseQueue} from "./core/RebaseQueue.sol";

abstract contract FUStorage is INonces, IERC5805 {
    mapping(address account => Shares shares) internal _sharesOf;
    Tokens internal _totalSupply;
    Shares internal _totalShares;
    mapping(address owner => mapping(address spender => CrazyBalance allowed)) internal _allowance;
    mapping(address account => address delegatee) public override delegates;
    Checkpoints internal _checkpoints;
    RebaseQueue internal _rebaseQueue;
    mapping(address account => uint256 nonce) public override nonces;
}
