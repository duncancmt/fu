// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {uint512, tmp, alloc} from "../lib/512Math.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";
import {ReflectMath} from "./ReflectMath.sol";

library Settings {
    using UnsafeMath for uint256;

    uint256 internal constant INITIAL_LIQUIDITY_DIVISOR = 10;
    // This constant can be set as low as 2 without breaking anything. Setting
    // it near to INITIAL_LIQUIDITY_DIVISOR will cause unexpected reverts.
    // TODO: verify that it's still possible to `deliver` without serious issue
    // even when the balance is well above the limit
    uint256 internal constant ANTI_WHALE_DIVISOR = 4;

    uint256 internal constant MIN_FEE = 1;
    // A fee above `ReflectMath.feeBasis / 2` makes ReflectMath break down
    uint256 internal constant MAX_FEE = ReflectMath.feeBasis / 2;

    uint256 private constant _UNISWAPV2_MAX_BALANCE = type(uint112).max;

    uint8 internal constant DECIMALS = 36;
    uint256 internal constant INITIAL_SUPPLY = _UNISWAPV2_MAX_BALANCE * type(uint32).max;
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 32;

    // Alternative
    /*
    uint8 internal constant DECIMALS = 27;
    uint256 internal constant INITIAL_SUPPLY = uint256(type(uint112).max);
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 80;
    */

    uint256 internal constant INITIAL_SHARES_RATIO = INITIAL_SHARES / INITIAL_SUPPLY;
    uint256 internal constant MIN_SHARES_RATIO = 10000; // below this, ReflectMath breaks down
    // bisecting: lo = 10000; hi =

    uint256 internal constant CRAZY_BALANCE_BASIS = INITIAL_SUPPLY / _UNISWAPV2_MAX_BALANCE;
    uint256 internal constant ADDRESS_DIVISOR = 2 ** 160 / (CRAZY_BALANCE_BASIS + 1);

    function oneTokenInShares() internal pure returns (uint256) {
        uint512 initialSharesTimesOneToken = alloc().omul(INITIAL_SHARES, 10 ** DECIMALS);
        uint256 result = initialSharesTimesOneToken.div(INITIAL_SUPPLY);
        if (tmp().omul(result, INITIAL_SUPPLY) < initialSharesTimesOneToken) {
            result = result.unsafeInc();
        }
        return result;
    }
}
