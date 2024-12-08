// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReflectMath} from "./ReflectMath.sol";

import {BasisPoints, BASIS} from "../types/BasisPoints.sol";
import {Shares} from "../types/Shares.sol";
import {Tokens} from "../types/Tokens.sol";
import {TokensXShares, alloc, tmp} from "../types/TokensXShares.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

library Settings {
    using UnsafeMath for uint256;

    uint256 internal constant INITIAL_LIQUIDITY_DIVISOR = 10;
    // An amount of shares above `totalShares / 4` makes `ReflectMath` break down. Also setting it
    // near to `INITIAL_LIQUIDITY_DIVISOR` will cause unexpected reverts.
    // TODO: verify that it's still possible to `deliver` without serious issue even when the
    // balance is well above the limit
    uint256 internal constant ANTI_WHALE_DIVISOR = 4;

    BasisPoints internal constant MIN_TAX = BasisPoints.wrap(1);
    // A tax above `BASIS / 2` makes `ReflectMath` break down
    BasisPoints internal constant MAX_TAX = BasisPoints.wrap(BasisPoints.unwrap(BASIS) / 2);

    uint256 private constant _UNISWAPV2_MAX_BALANCE = type(uint112).max;

    uint8 internal constant DECIMALS = 36;
    uint256 internal constant CRAZY_BALANCE_BASIS = 2 ** 31 - 1; // This ensures no overflow in ReflectMath
    Tokens internal constant INITIAL_SUPPLY = Tokens.wrap(_UNISWAPV2_MAX_BALANCE * CRAZY_BALANCE_BASIS * ANTI_WHALE_DIVISOR);
    Shares internal constant INITIAL_SHARES = Shares.wrap(Tokens.unwrap(INITIAL_SUPPLY) << 32);

    uint256 internal constant INITIAL_SHARES_RATIO = Shares.unwrap(INITIAL_SHARES) / Tokens.unwrap(INITIAL_SUPPLY);
    uint256 internal constant MIN_SHARES_RATIO = 5; // below this, `ReflectMath` breaks down

    uint256 internal constant ADDRESS_DIVISOR = 2 ** 160 / (CRAZY_BALANCE_BASIS + 1);

    // This constant is intertwined with a bunch of hex literals in `Checkpoints.sol`, because
    // Solidity has poor support for introspecting the range of user-defined types and for defining
    // constants dependant on values in other translation units. If you change this, make
    // appropriate changes over there, and be sure to run the invariant/property tests.
    uint256 internal constant SHARES_TO_VOTES_DIVISOR = 2 ** 32;
    // Where there are no *wrong* values for this constant, setting it to the ratio between the
    // voting period and the clock quantum optimizes gas.
    uint256 internal constant BISECT_WINDOW_DEFAULT = 7;

    function oneTokenInShares() internal pure returns (Shares) {
        TokensXShares initialSharesTimesOneToken = alloc().omul(INITIAL_SHARES, Tokens.wrap(10 ** DECIMALS));
        Shares result = initialSharesTimesOneToken.div(INITIAL_SUPPLY);
        result = result.inc(tmp().omul(result, INITIAL_SUPPLY) < initialSharesTimesOneToken);
        return result;
    }
}
