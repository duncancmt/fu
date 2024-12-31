// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Shares} from "./Shares.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

/// This type is given as `uint256` for efficiency, but it is actually only 191 bits.
type SharesXBasisPoints is uint256;

function scale(Shares s, BasisPoints bp) pure returns (SharesXBasisPoints) {
    unchecked {
        return SharesXBasisPoints.wrap(Shares.unwrap(s) * BasisPoints.unwrap(bp));
    }
}

function cast(SharesXBasisPoints tbp) pure returns (Shares) {
    return Shares.wrap(UnsafeMath.unsafeDiv(SharesXBasisPoints.unwrap(tbp), BasisPoints.unwrap(BASIS)));
}

function __add(SharesXBasisPoints a, SharesXBasisPoints b) pure returns (SharesXBasisPoints) {
    unchecked {
        return SharesXBasisPoints.wrap(SharesXBasisPoints.unwrap(a) + SharesXBasisPoints.unwrap(b));
    }
}

function __sub(SharesXBasisPoints a, SharesXBasisPoints b) pure returns (SharesXBasisPoints) {
    unchecked {
        return SharesXBasisPoints.wrap(SharesXBasisPoints.unwrap(a) - SharesXBasisPoints.unwrap(b));
    }
}

using {__add as +, __sub as -} for SharesXBasisPoints global;
