// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "../core/Settings.sol";

import {BasisPoints, BASIS} from "../types/BasisPoints.sol";
import {Shares, ONE as ONE_SHARE} from "../types/Shares.sol";
import {Tokens, ONE as ONE_TOKEN} from "../types/Tokens.sol";
import {scale} from "../types/SharesXBasisPoints.sol";
import {TokensXBasisPoints, scale, castUp, cast} from "../types/TokensXBasisPoints.sol";
import {TokensXShares, tmp, alloc, SharesToTokens} from "../types/TokensXShares.sol";
import {TokensXShares2, tmp as tmp2, alloc as alloc2} from "../types/TokensXShares2.sol";
import {TokensXBasisPointsXShares, tmp as tmp3, alloc as alloc3} from "../types/TokensXBasisPointsXShares.sol";
import {TokensXBasisPointsXShares2, tmp as tmp4, alloc as alloc4} from "../types/TokensXBasisPointsXShares2.sol";
import {SharesXBasisPoints, scale, castUp, cast} from "../types/SharesXBasisPoints.sol";
import {Shares2XBasisPoints, tmp as tmp5, alloc as alloc5} from "../types/Shares2XBasisPoints.sol";

import {UnsafeMath} from "../lib/UnsafeMath.sol";

library ReflectMath {
    using UnsafeMath for uint256;
    using SharesToTokens for Shares;

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
        TokensXBasisPointsXShares2 n1 = alloc().omul(fromShares, totalSupply).isub(tmp().omul(amount, totalShares)).imul(scale(uninvolvedShares, BASIS));
        TokensXBasisPointsXShares t4 = alloc3().omul(totalSupply, scale(uninvolvedShares, BASIS));
        TokensXBasisPointsXShares t5 = alloc3().omul(amount, scale(totalShares, taxRate));
        TokensXBasisPointsXShares d = alloc3().oadd(t4, t5);
        TokensXBasisPointsXShares t6 = alloc3().omul(amount, scale(totalShares, BASIS - taxRate));
        TokensXBasisPointsXShares t7 = alloc3().omul(scale(toShares, BASIS), totalSupply);
        TokensXBasisPointsXShares t8 = alloc3().oadd(t6, t7);
        TokensXBasisPointsXShares2 n2 = alloc4().omul(t8, uninvolvedShares);

        (newFromShares, newToShares) = n1.divMulti(n2, d);
        newTotalShares = totalShares + (newToShares - toShares) - (fromShares - newFromShares);

        (Tokens beforeFromBalance, Tokens beforeToBalance) =
            fromShares.toTokensMulti(toShares, totalSupply, totalShares);

        Tokens afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedAfterToBalanceLo = beforeToBalance + amount - castUp(scale(amount, taxRate));
        //Tokens expectedAfterToBalanceHi = beforeToBalance + castUp(scale(amount, BASIS - taxRate));

        if (afterToBalance < expectedAfterToBalanceLo) {
            {
                Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(totalSupply)));
                newToShares = newToShares + incr;
                newTotalShares = newTotalShares + incr;
            }
            Tokens afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            Tokens expectedAfterFromBalance = beforeFromBalance - amount;
            if (afterFromBalance < expectedAfterFromBalance) {
                Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(totalSupply)));
                newFromShares = newFromShares + incr;
                newTotalShares = newTotalShares + incr;
            }
        }
        // TODO: previously the block below was an `else` block. This is more accurate, but it is *MUCH* less gas efficient
        {
            Tokens afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            Tokens expectedAfterFromBalance = beforeFromBalance - amount;
            {
                bool condition = afterFromBalance > expectedAfterFromBalance;
                newFromShares = newFromShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterFromBalance < expectedAfterFromBalance;
                newFromShares = newFromShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }

            afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
            {
                bool condition = afterToBalance > expectedAfterToBalanceLo;
                newToShares = newToShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterToBalance < expectedAfterToBalanceLo;
                newToShares = newToShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }

            afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
            {
                bool condition = afterFromBalance > expectedAfterFromBalance;
                newFromShares = newFromShares.dec(condition);
                newTotalShares = newTotalShares.dec(condition);
            }
            {
                bool condition = afterFromBalance < expectedAfterFromBalance;
                newFromShares = newFromShares.inc(condition);
                newTotalShares = newTotalShares.inc(condition);
            }
        }

        if (newTotalShares > totalShares) {
            // TODO: check to see if this branch is still necessary
            Shares decrTotal = newTotalShares - totalShares;
            Shares decrFrom;
            Shares decrTo;
            if (newFromShares > newToShares) {
                decrFrom = Shares.wrap(
                    Shares.unwrap(decrTotal) * Shares.unwrap(newFromShares) / Shares.unwrap(newFromShares + newToShares)
                );
                decrTo = decrTotal - decrFrom;
            } else {
                decrTo = Shares.wrap(
                    Shares.unwrap(decrTotal) * Shares.unwrap(newToShares) / Shares.unwrap(newFromShares + newToShares)
                );
                decrFrom = decrTotal - decrTo;
            }
            newTotalShares = totalShares;
            newFromShares = newFromShares - decrFrom;
            newToShares = newToShares - decrTo;
        }
    }

    function getTransferShares(
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares
    ) internal pure freeMemory returns (Shares newToShares, Shares newTotalShares) {
        // Called when `from` is sending their entire balance
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        Shares2XBasisPoints n = alloc5().omul(scale(uninvolvedShares, BASIS), totalShares);
        SharesXBasisPoints d = scale(uninvolvedShares, BASIS) + scale(fromShares, taxRate);

        newTotalShares = n.div(d);
        newToShares = toShares + fromShares - (totalShares - newTotalShares);

        // Fixup rounding error
        (Tokens beforeFromBalance, Tokens beforeToBalance) =
            fromShares.toTokensMulti(toShares, totalSupply, totalShares);
        Tokens afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedAfterToBalance = beforeToBalance + beforeFromBalance - castUp(scale(beforeFromBalance, taxRate));

        for (uint256 i; afterToBalance > expectedAfterToBalance && i < 3; i++) {
            Shares decr = Shares.wrap(
                (Tokens.unwrap(afterToBalance - expectedAfterToBalance) * Shares.unwrap(newTotalShares)).unsafeDivUp(
                    Tokens.unwrap(totalSupply)
                )
            );
            newToShares = newToShares - decr;
            newTotalShares = newTotalShares - decr;
            if (newToShares <= toShares) {
                newTotalShares = newTotalShares + (toShares - newToShares);
                newToShares = toShares;
                afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
                break;
            }
            afterToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        }
        {
            bool condition = afterToBalance < expectedAfterToBalance;
            newToShares = newToShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }
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
        TokensXShares t1 = alloc().omul(totalShares.mul(Settings.ANTI_WHALE_DIVISOR), totalSupply + amount);
        TokensXShares t2 = alloc().omul(fromShares.mul(Settings.ANTI_WHALE_DIVISOR) + totalShares, totalSupply);
        TokensXShares d = alloc().osub(t1, t2);
        Shares uninvolvedShares = totalShares - fromShares - toShares;
        TokensXShares2 n1 =
            alloc2().omul(tmp().omul(totalShares.mul(Settings.ANTI_WHALE_DIVISOR), totalSupply), uninvolvedShares);
        TokensXShares t3 = alloc().omul(fromShares, totalSupply);
        TokensXShares t4 = alloc().omul(totalShares, amount);
        TokensXShares2 n2 = alloc2().omul(uninvolvedShares.mul(Settings.ANTI_WHALE_DIVISOR), tmp().osub(t3, t4));

        (newToShares, newFromShares) = n1.divMulti(n2, d);
        newToShares = newToShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        newTotalShares = totalShares - (fromShares + toShares - newFromShares - newToShares);
        counterfactualToShares = tmp3().omul(
            scale(totalSupply, BASIS.div(Settings.ANTI_WHALE_DIVISOR)) - scale(amount, BASIS - taxRate), totalShares
        ).div(scale(totalSupply, BASIS));

        // Fixup rounding error
        {
            bool condition = newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
            newTotalShares = newTotalShares.dec(condition);
            newToShares = newToShares.dec(condition);
        }

        Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
        Tokens afterFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedAfterFromBalance = beforeFromBalance - amount;
        {
            bool condition = afterFromBalance > expectedAfterFromBalance;
            newFromShares = newFromShares.dec(condition);
            newTotalShares = newTotalShares.dec(condition);
        }
        {
            bool condition = afterFromBalance < expectedAfterFromBalance;
            newFromShares = newFromShares.inc(condition);
            newTotalShares = newTotalShares.inc(condition);
        }

        {
            bool condition = newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
            newTotalShares = newTotalShares.dec(condition);
            newToShares = newToShares.dec(condition);
        }
    }

    function getTransferSharesToWhale(BasisPoints taxRate, Shares totalShares, Shares fromShares, Shares toShares)
        internal
        pure
        freeMemory
        returns (Shares counterfactualToShares, Shares newToShares, Shares newTotalShares)
    {
        // Called when `to`'s final shares will be the whale limit and `from` is sending their entire balance
        newToShares = (totalShares - fromShares - toShares).div(Settings.ANTI_WHALE_DIVISOR - 1) - ONE_SHARE;
        counterfactualToShares =
            cast(scale(totalShares, BASIS.div(Settings.ANTI_WHALE_DIVISOR)) - scale(fromShares, BASIS - taxRate));
        newTotalShares = totalShares + newToShares - fromShares - toShares;

        // Fixup rounding error
        bool condition = newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        newTotalShares = newTotalShares.dec(condition);
        newToShares = newToShares.dec(condition);
    }

    function getTransferSharesFromPair(
        BasisPoints taxRate,
        Tokens totalSupply,
        Shares totalShares,
        Tokens amount,
        Shares toShares
    ) internal view freeMemory returns (Shares newToShares, Shares newTotalShares, Tokens newTotalSupply) {
        TokensXBasisPointsXShares t2 = alloc3().omul(scale(amount, BASIS - taxRate), totalShares);
        TokensXBasisPointsXShares t4 = alloc3().omul(scale(totalSupply, BASIS), toShares);
        TokensXBasisPointsXShares t5 = alloc3().oadd(t2, t4);
        TokensXBasisPointsXShares2 n = alloc4().omul(t5, totalShares - toShares);

        TokensXBasisPointsXShares t7 = alloc3().omul(scale(totalSupply, BASIS), totalShares);
        TokensXBasisPointsXShares t9 = alloc3().omul(scale(amount, taxRate), totalShares);
        TokensXBasisPointsXShares t10 = alloc3().oadd(t9, t7);
        TokensXBasisPointsXShares d = alloc3().osub(t10, t4);

        newToShares = n.div(d);
        newTotalShares = newToShares - toShares + totalShares;
        newTotalSupply = totalSupply + amount;

        // Fixup rounding error
        Tokens beforeToBalance = toShares.toTokens(totalSupply, totalShares);
        Tokens afterToBalance = newToShares.toTokens(newTotalSupply, newTotalShares);
        Tokens expectedAfterToBalanceLo = beforeToBalance + amount - castUp(scale(amount, taxRate));

        if (afterToBalance < expectedAfterToBalanceLo) {
            Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(newTotalSupply)));
            newToShares = newToShares + incr;
            newTotalShares = newTotalShares + incr;
        }
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
        TokensXBasisPointsXShares t1 = alloc3().omul(scale(fromShares, BASIS), totalSupply);
        TokensXBasisPointsXShares t2 = alloc3().omul(scale(totalShares, BASIS), amount);
        TokensXBasisPointsXShares t3 = alloc3().osub(t1, t2);
        TokensXBasisPointsXShares2 n = alloc4().omul(t3, totalShares - fromShares);

        TokensXBasisPointsXShares t4 = alloc3().omul(scale(totalShares, taxRate), amount);
        TokensXBasisPointsXShares t5 = alloc3().omul(scale(totalShares - fromShares, BASIS), totalSupply);
        TokensXBasisPointsXShares d = alloc3().oadd(t4, t5);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);
        transferTokens = cast(scale(amount, BASIS - taxRate));
        newTotalSupply = totalSupply - transferTokens;

        // Fixup rounding error
        Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
        Tokens afterFromBalance = newFromShares.toTokens(newTotalSupply, newTotalShares);
        Tokens expectedAfterFromBalance = beforeFromBalance - amount;

        if (afterFromBalance < expectedAfterFromBalance) {
            Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(newTotalSupply)));
            newFromShares = newFromShares + incr;
            newTotalShares = newTotalShares + incr;
        } else if (afterFromBalance > expectedAfterFromBalance) {
            Shares decr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(newTotalSupply)));
            newFromShares = newFromShares - decr;
            newTotalShares = newTotalShares - decr;
        }
    }

    function getDeliverShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        view
        freeMemory
        returns (Shares newFromShares, Shares newTotalShares)
    {
        TokensXShares t1 = alloc().omul(fromShares, totalSupply);
        TokensXShares t2 = alloc().omul(amount, totalShares);
        TokensXShares t3 = alloc().osub(t1, t2);
        TokensXShares2 n = alloc2().omul(t3, totalShares - fromShares);
        TokensXShares t4 = alloc().omul(totalSupply, totalShares - fromShares);
        TokensXShares d = alloc().oadd(t4, t2);

        newFromShares = n.div(d);
        newTotalShares = totalShares - (fromShares - newFromShares);

        // Fixup rounding error
        Tokens beforeFromBalance = tmp().omul(fromShares, totalSupply).div(totalShares);
        Tokens afterFromBalance = tmp().omul(newFromShares, totalSupply).div(newTotalShares);
        Tokens expectedAfterFromBalance = beforeFromBalance - amount;
        bool condition = afterFromBalance < expectedAfterFromBalance;
        newFromShares = newFromShares.inc(condition);
        newTotalShares = newTotalShares.inc(condition);
    }

    // getDeliverShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward

    function getBurnShares(Tokens amount, Tokens totalSupply, Shares totalShares, Shares fromShares)
        internal
        pure
        freeMemory
        returns (Shares newFromShares, Shares newTotalShares, Tokens newTotalSupply)
    {
        TokensXShares t1 = alloc().omul(fromShares, totalSupply);
        TokensXShares t2 = alloc().omul(totalShares, amount);
        TokensXShares n = alloc().osub(t1, t2);
        newFromShares = n.div(totalSupply);
        newTotalShares = totalShares + newFromShares - fromShares;
        newTotalSupply = totalSupply - amount;

        // Fixup rounding error
        Tokens beforeFromBalance = fromShares.toTokens(totalSupply, totalShares);
        Tokens afterFromBalance = newFromShares.toTokens(newTotalSupply, newTotalShares);
        Tokens expectedAfterFromBalance = beforeFromBalance - amount;

        if (afterFromBalance < expectedAfterFromBalance) {
            Shares incr = Shares.wrap(Shares.unwrap(newTotalShares).unsafeDiv(Tokens.unwrap(newTotalSupply)));
            newFromShares = newFromShares + incr;
            newTotalShares = newTotalShares + incr;
        }
    }

    // getBurnShares(Tokens,Shares,Shares) is not provided because it's extremely straightforward
}
