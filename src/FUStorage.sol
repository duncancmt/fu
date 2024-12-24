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
    // @custom:storage-location erc7201:"Fuck You!"
    struct Storage {
        mapping(address account => Shares shares) sharesOf;
        Tokens totalSupply;
        Tokens pairTokens;
        Shares totalShares;
        mapping(address owner => mapping(address spender => CrazyBalance allowed)) allowance;
        mapping(address account => address delegatee) delegates;
        Checkpoints checkpoints;
        RebaseQueue rebaseQueue;
        mapping(address account => uint256 nonce) nonces;
    }

    function delegates(address account) external view override returns (address delegatee) {
        return _s().delegates[account];
    }

    function nonces(address account) external view override returns (uint256 nonce) {
        return _s().nonces[account];
    }

    constructor() {
        Storage storage s = _s();
        uint256 sInt;
        assembly ("memory-safe") {
            sInt := s.slot
        }
        assert(sInt == (uint256(keccak256("Fuck You!")) - 1) & uint256(int256(~0xff)));
    }


    function _s() internal pure returns (Storage storage r) {
        assembly ("memory-safe") {
            r.slot := 0xb614ddaf8c6c224524c95dbfcb82a82be086ec3a639808bbda893d5b4ac93600
        }
    }
}
