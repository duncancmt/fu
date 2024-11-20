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
    uint256 internal constant ANTI_WHALE_DIVISOR = 4;

    uint256 internal constant MIN_FEE = 1;
    // If the fee is set above `ReflectMath.feeBasis / 2`, the reflection math
    // breaks down.
    uint256 internal constant MAX_FEE = ReflectMath.feeBasis / 2;

    uint8 internal constant DECIMALS = 36;
    uint256 internal constant INITIAL_SUPPLY = uint256(type(uint112).max) * type(uint32).max;
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 32;

    // Alternative
    /*
    uint8 internal constant DECIMALS = 27;
    uint256 internal constant INITIAL_SUPPLY = uint256(type(uint112).max);
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 80;
    */

    uint256 internal constant CRAZY_BALANCE_BASIS = INITIAL_SUPPLY / type(uint112).max;
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
