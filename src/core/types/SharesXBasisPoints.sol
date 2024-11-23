// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasisPoints, BASIS} from "./BasisPoints.sol";
import {Shares} from "./Shares.sol";

import {UnsafeMath} from "../../lib/UnsafeMath.sol";

type SharesXBasisPoints is uint256;

function scale(Shares s, BasisPoints bp) pure returns (SharesXBasisPoints) {
    unchecked {
        return SharesXBasisPoints.wrap(Shares.unwrap(s) * BasisPoints.unwrap(bp));
    }
}

function cast(SharesXBasisPoints sbp) pure returns (Shares) {
    return Shares.wrap(SharesXBasisPoints.unwrap(sbp) / BasisPoints.unwrap(BASIS));
}

function castUp(SharesXBasisPoints sbp) pure returns (Shares) {
    return Shares.wrap(UnsafeMath.unsafeDivUp(SharesXBasisPoints.unwrap(sbp), BasisPoints.unwrap(BASIS)));
}
