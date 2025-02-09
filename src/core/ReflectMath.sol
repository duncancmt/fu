// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "../core/Settings.sol";

import {BasisPoints, BASIS} from "../types/BasisPoints.sol";
import {Shares, ONE as ONE_SHARE} from "../types/Shares.sol";
import {Tokens} from "../types/Tokens.sol";
import {TokensXBasisPoints, scale, cast} from "../types/TokensXBasisPoints.sol";
import {TokensXShares, tmp as tmpTS, alloc as allocTS} from "../types/TokensXShares.sol";
import {TokensXShares2} from "../types/TokensXShares2.sol";
import {TokensXBasisPointsXShares, tmp as tmpTBpS, alloc as allocTBpS} from "../types/TokensXBasisPointsXShares.sol";
import {TokensXBasisPointsXShares2} from "../types/TokensXBasisPointsXShares2.sol";
import {SharesXBasisPoints, scale, cast} from "../types/SharesXBasisPoints.sol";
import {Shares2XBasisPoints, alloc as allocS2Bp} from "../types/Shares2XBasisPoints.sol";

/*

WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING
  ***                                                                     ***
WARNING                     This code is unaudited                      WARNING
  ***                                                                     ***
WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING *** WARNING

*/

library ReflectMath {
    modifier freeMemory() {
        uint256 freePtr;
        assembly ("memory-safe") {
            freePtr := mload(0x40)
        }
        _;
        assembly ("memory-safe") {
            mstore(0x40, freePtr)
        }
    }

    // TODO: reorder arguments for clarity/consistency
    function getTransferShares(
        Tokens amount,
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal view freeMemory returns (Shares newFromShares, Shares newToShares, Shares newTotalShares) {
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        TokensXBasisPointsXShares2 n0 = allocTS().omul(fromShares, totalSupply).isub(tmpTS().omul(amount, totalShares))
            .imul(scale(uninvolvedShares, BASIS));
        TokensXBasisPointsXShares d = allocTBpS().omul(totalSupply, scale(uninvolvedShares, BASIS)).iadd(
            tmpTBpS().omul(amount, scale(totalShares, taxRate))
        );
        TokensXBasisPointsXShares2 n1 = allocTBpS().omul(amount, scale(totalShares, BASIS - taxRate)).iadd(
            tmpTBpS().omul(scale(toShares, BASIS), totalSupply)
        ).imul(uninvolvedShares);

        (newFromShares, newToShares) = n0.divMulti(n1, d);
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);
    }

    function getTransferShares(BasisPoints taxRate, Shares totalShares, Shares fromShares, Shares toShares)
        internal
        pure
        freeMemory
        returns (Shares newToShares, Shares newTotalShares)
    {
        // Called when `from` is sending their entire balance
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        Shares2XBasisPoints n = allocS2Bp().omul(scale(uninvolvedShares, BASIS), totalShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, taxRate);

        newTotalShares = n.div(d);
        newToShares = toShares + fromShares - (totalShares - newTotalShares);
    }

    function getTransferSharesToWhale(
        Tokens amount,
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    )
        internal
        view
        freeMemory
        returns (Shares newFromShares, Shares counterfactualToShares, Shares newToShares, Shares newTotalShares)
    {
        // Called when `to`'s final shares will be the whale limit
        TokensXShares d = allocTS().omul(totalShares.mul(Settings.ANTI_WHALE_DIVISOR), totalSupply + amount).isub(
            tmpTS().omul(fromShares.mul(Settings.ANTI_WHALE_DIVISOR) + totalShares, totalSupply)
        );
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        TokensXShares2 n0 =
            allocTS().omul(totalShares.mul(Settings.ANTI_WHALE_DIVISOR), totalSupply).imul(uninvolvedShares);
        TokensXShares2 n1 = allocTS().omul(fromShares, totalSupply).isub(tmpTS().omul(totalShares, amount)).imul(
            uninvolvedShares.mul(Settings.ANTI_WHALE_DIVISOR)
        );

        (newToShares, newFromShares) = n0.divMulti(n1, d);
        newToShares = newToShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        newTotalShares = totalShares - (fromShares + toShares - newFromShares - newToShares);
        counterfactualToShares = tmpTBpS().omul(
            scale(totalSupply, BASIS.div(Settings.ANTI_WHALE_DIVISOR)) - scale(amount, BASIS - taxRate), totalShares
        ).div(scale(totalSupply, BASIS));
    }

    function getTransferSharesToWhale(BasisPoints taxRate, Shares totalShares, Shares fromShares, Shares toShares)
        internal
        pure
        returns (Shares counterfactualToShares, Shares newToShares, Shares newTotalShares)
    {
        // Called when `to`'s final shares will be the whale limit and `from` is sending their entire balance
        newToShares = (totalShares - fromShares - toShares).div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE) - ONE_SHARE;
        counterfactualToShares =
            cast(scale(totalShares, BASIS.div(Settings.ANTI_WHALE_DIVISOR)) - scale(fromShares, BASIS - taxRate));
        newTotalShares = totalShares + newToShares - fromShares - toShares;
    }

    function getTransferSharesFromPair(
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Tokens amount,
        Shares toShares
    ) internal view freeMemory returns (Shares newToShares, Shares newTotalShares, Tokens newTotalSupply) {
        TokensXBasisPointsXShares d = allocTBpS().omul(scale(totalSupply, BASIS), totalShares).iadd(
            tmpTBpS().omul(scale(amount, taxRate), totalShares)
        );
        TokensXBasisPointsXShares t = tmpTBpS().omul(scale(totalSupply, BASIS), toShares);
        // slither-disable-next-line unused-return
        d.isub(t);
        TokensXBasisPointsXShares2 n =
            allocTBpS().omul(scale(amount, BASIS - taxRate), totalShares).iadd(t).imul(totalShares - toShares);

        newToShares = n.div(d);
        newTotalShares = totalShares + newToShares - toShares;
        newTotalSupply = totalSupply + amount;
    }

    function getTransferSharesToPair(
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Tokens amount,
        Shares fromShares
    )
        internal
        view
        freeMemory
        returns (Shares newFromShares, Shares newTotalShares, Tokens transferTokens, Tokens newTotalSupply)
    {
        TokensXBasisPointsXShares2 n = allocTBpS().omul(scale(fromShares, BASIS), totalSupply).isub(
            tmpTBpS().omul(scale(totalShares, BASIS), amount)
        ).imul(totalShares - fromShares);

        TokensXBasisPointsXShares d = allocTBpS().omul(scale(totalShares, taxRate), amount).iadd(
            tmpTBpS().omul(scale(totalShares - fromShares, BASIS), totalSupply)
        );

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);
        transferTokens = cast(scale(amount, BASIS - taxRate));
        newTotalSupply = totalSupply - transferTokens;
    }

    function getDeliverShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        freeMemory
        returns (Shares newFromShares, Shares newTotalShares)
    {
        TokensXShares d = allocTS().omul(totalSupply, totalShares - fromShares);
        TokensXShares t = tmpTS().omul(amount, totalShares);
        // slither-disable-next-line unused-return
        d.iadd(t);
        TokensXShares2 n = allocTS().omul(fromShares, totalSupply).isub(t).imul(totalShares - fromShares);

        newFromShares = n.div(d);
        newTotalShares = totalShares + newFromShares - fromShares;
    }

    // getDeliverShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward

    function getBurnShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        pure
        freeMemory
        returns (Shares newFromShares, Shares newTotalShares, Tokens newTotalSupply)
    {
        TokensXShares n = allocTS().omul(fromShares, totalSupply).isub(tmpTS().omul(totalShares, amount));
        newFromShares = n.div(totalSupply);
        newTotalShares = totalShares + newFromShares - fromShares;
        newTotalSupply = totalSupply - amount;
    }

    // getBurnShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward
}
