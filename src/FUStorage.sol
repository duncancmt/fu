// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {INonces} from "./interfaces/INonces.sol";
import {IERC5805} from "./interfaces/IERC5805.sol";

import {Tokens} from "./types/Tokens.sol";
import {Shares, SharesStorage} from "./types/Shares.sol";
import {CrazyBalance} from "./types/CrazyBalance.sol";

import {Checkpoints} from "./core/Checkpoints.sol";
import {RebaseQueue} from "./core/RebaseQueue.sol";

abstract contract FUStorage is IERC20, INonces, IERC5805 {
    struct Storage {
        mapping(address account => SharesStorage shares) sharesOf;
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
        return _$().delegates[account];
    }

    function nonces(address account) external view override returns (uint256 nonce) {
        return _$().nonces[account];
    }

    string public constant override name = "Fuck You!";

    constructor() {
        Storage storage $ = _$();
        uint256 $int;
        assembly ("memory-safe") {
            $int := $.slot
        }
        assert($int == uint128(uint256(keccak256(bytes(name))) - 1) & ~uint256(0xff));
    }

    // slither-disable-next-line naming-convention
    function _$() internal pure returns (Storage storage $) {
        assembly ("memory-safe") {
            $.slot := 0xe086ec3a639808bbda893d5b4ac93600
        }
    }
}
