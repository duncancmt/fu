// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Shares, ONE as ONE_SHARE, ternary, maybeSwap} from "../types/Shares.sol";
import {Settings} from "./Settings.sol";

function whaleLimit(Shares shares, Shares totalShares) pure returns (Shares limit, Shares newTotalShares) {
    Shares uninvolved = totalShares - shares;
    limit = uninvolved.div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE) - ONE_SHARE;
    newTotalShares = uninvolved + limit;
}

function applyWhaleLimit(Shares shares, Shares totalShares) pure returns (Shares, Shares) {
    (Shares limit, Shares newTotalShares) = whaleLimit(shares, totalShares);
    bool condition = shares > limit;
    return (ternary(condition, limit, shares), ternary(condition, newTotalShares, totalShares));
}

function applyWhaleLimit(Shares shares0, Shares shares1, Shares totalShares) pure returns (Shares, Shares, Shares) {
    bool condition = shares0 > shares1;
    (Shares sharesLo, Shares sharesHi) = maybeSwap(condition, shares0, shares1);
    (Shares firstLimit, Shares newTotalShares) = whaleLimit(sharesHi, totalShares);
    if (sharesHi > firstLimit) {
        Shares uninvolved = totalShares - sharesHi - sharesLo;
        Shares secondLimit = uninvolved.div(Settings.ANTI_WHALE_DIVISOR_MINUS_TWO) - ONE_SHARE;
        if (sharesLo > secondLimit) {
            totalShares = uninvolved + secondLimit.mul(2);
            sharesHi = secondLimit;
            sharesLo = secondLimit;
        } else {
            totalShares = newTotalShares;
            sharesHi = firstLimit;
        }
    }
    (shares0, shares1) = maybeSwap(condition, sharesLo, sharesHi);
    return (shares0, shares1, totalShares);
}
