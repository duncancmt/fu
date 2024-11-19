// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {uint512, tmp, alloc} from "../lib/512Math.sol";
import {UnsafeMath} from "../lib/UnsafeMath.sol";

library Settings {
    using UnsafeMath for uint256;

    uint8 internal constant DECIMALS = 36;
    uint256 internal constant INITIAL_SUPPLY = uint256(type(uint112).max) * type(uint40).max;
    uint256 internal constant INITIAL_SHARES = INITIAL_SUPPLY << 20;

    function oneTokenInShares() internal pure returns (uint256) {
        uint512 initialSharesTimesOneToken = alloc().omul(INITIAL_SHARES, 10 ** DECIMALS);
        uint256 result = initialSharesTimesOneToken.div(INITIAL_SUPPLY);
        if (tmp().omul(result, INITIAL_SUPPLY) < initialSharesTimesOneToken) {
            result = result.unsafeInc();
        }
        return result;
    }
}
