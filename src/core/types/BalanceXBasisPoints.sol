// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Balance} from "./Balance.sol";

import {UnsafeMath} from "../../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is actually only 158 bits.
type BalanceXBasisPoints is uint256;

function scale(Balance s, BasisPoints bp) pure returns (BalanceXBasisPoints) {
    unchecked {
        return BalanceXBasisPoints.wrap(Balance.unwrap(s) * BasisPoints.unwrap(bp));
    }
}

function castUp(BalanceXBasisPoints sbp) pure returns (Balance) {
    return Balance.wrap(UnsafeMath.unsafeDivUp(BalanceXBasisPoints.unwrap(sbp), BasisPoints.unwrap(BASIS)));
}
