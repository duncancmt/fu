// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReflectMath} from "./ReflectMath.sol";

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares} from "./types/Shares.sol";
import {Balance} from "./types/Balance.sol";
import {BalanceXShares, alloc, tmp} from "./types/BalanceXShares.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

library Settings {
    using UnsafeMath for uint256;

    uint256 internal constant INITIAL_LIQUIDITY_DIVISOR = 10;
    // This constant can be set as low as 2 without breaking anything. Setting
    // it near to INITIAL_LIQUIDITY_DIVISOR will cause unexpected reverts.
    // TODO: verify that it's still possible to `deliver` without serious issue
    // even when the balance is well above the limit
    uint256 internal constant ANTI_WHALE_DIVISOR = 4;

    BasisPoints internal constant MIN_FEE = BasisPoints.wrap(1);
    // A fee above `ReflectMath.feeBasis / 2` makes ReflectMath break down
    BasisPoints internal constant MAX_FEE = BasisPoints.wrap(BasisPoints.unwrap(BASIS) / 2);

    uint256 private constant _UNISWAPV2_MAX_BALANCE = type(uint112).max;

    uint8 internal constant DECIMALS = 36;
    Balance internal constant INITIAL_SUPPLY = Balance.wrap(_UNISWAPV2_MAX_BALANCE * type(uint32).max);
    Shares internal constant INITIAL_SHARES = Shares.wrap(Balance.unwrap(INITIAL_SUPPLY) << 32);

    uint256 internal constant INITIAL_SHARES_RATIO = Shares.unwrap(INITIAL_SHARES) / Balance.unwrap(INITIAL_SUPPLY);
    uint256 internal constant MIN_SHARES_RATIO = 10000; // below this, ReflectMath breaks down
    // bisecting: lo = 10000; hi =

    uint256 internal constant CRAZY_BALANCE_BASIS = Balance.unwrap(INITIAL_SUPPLY) / _UNISWAPV2_MAX_BALANCE;
    uint256 internal constant ADDRESS_DIVISOR = 2 ** 160 / (CRAZY_BALANCE_BASIS + 1);

    function oneTokenInShares() internal pure returns (Shares) {
        BalanceXShares initialSharesTimesOneToken = alloc().omul(INITIAL_SHARES, Balance.wrap(10 ** DECIMALS));
        Shares result = initialSharesTimesOneToken.div(INITIAL_SUPPLY);
        result = result.inc(tmp().omul(result, INITIAL_SUPPLY) < initialSharesTimesOneToken);
        return result;
    }
}
