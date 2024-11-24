// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints} from "./BasisPoints.sol";
import {Shares} from "./Shares.sol";

type SharesXBasisPoints is uint256;

function scale(Shares s, BasisPoints bp) pure returns (SharesXBasisPoints) {
    unchecked {
        return SharesXBasisPoints.wrap(Shares.unwrap(s) * BasisPoints.unwrap(bp));
    }
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
