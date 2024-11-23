// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

type BasisPoints is uint16;

BasisPoints constant BASIS = BasisPoints.wrap(10_000);

function __sub(BasisPoints a, BasisPoints b) pure returns (BasisPoints) {
    unchecked {
        return BasisPoints.wrap(BasisPoints.unwrap(a) - BasisPoints.unwrap(b));
    }
}

using {__sub as -} for BasisPoints global;
