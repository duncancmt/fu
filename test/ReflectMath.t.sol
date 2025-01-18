// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";

import {BasisPoints, BASIS} from "src/types/BasisPoints.sol";
import {Shares, ONE as ONE_SHARE} from "src/types/Shares.sol";
import {Tokens} from "src/types/Tokens.sol";
import {TokensXShares, tmp, alloc, SharesToTokens} from "src/types/TokensXShares.sol";
import {TokensXBasisPoints, scale, cast, castUp} from "src/types/TokensXBasisPoints.sol";

import {UnsafeMath} from "src/lib/UnsafeMath.sol";

import {Test} from "@forge-std/Test.sol";
import {Boilerplate} from "./Boilerplate.sol";

contract ReflectMathTest is Boilerplate, Test {
    using UnsafeMath for uint256;
    using SharesToTokens for Shares;

    function _boundCommon(Tokens totalSupply, Shares totalShares, Shares fromShares, uint256 sharesRatio)
        internal
        pure
        returns (Tokens, Shares, Shares, Tokens)
    {
        totalSupply = Tokens.wrap(
            bound(Tokens.unwrap(totalSupply), 10 ** Settings.DECIMALS + 1 wei, Tokens.unwrap(Settings.INITIAL_SUPPLY))
        );
        sharesRatio = bound(sharesRatio, Settings.MIN_SHARES_RATIO, Settings.INITIAL_SHARES_RATIO);
        Shares maxShares = Shares.wrap(Tokens.unwrap(totalSupply) * (sharesRatio + 1) - 1 wei);
        maxShares = maxShares > Settings.INITIAL_SHARES ? Settings.INITIAL_SHARES : maxShares;
        totalShares = Shares.wrap(
            bound(Shares.unwrap(totalShares), Tokens.unwrap(totalSupply) * sharesRatio, Shares.unwrap(maxShares))
        );

        fromShares = Shares.wrap(
            bound(Shares.unwrap(fromShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE))
        );

        Tokens fromBalance = fromShares.toTokens(totalSupply, totalShares);
        return (totalSupply, totalShares, fromShares, fromBalance);
    }

    function _boundCommon(Tokens totalSupply, Shares totalShares, Shares fromShares, Tokens amount, uint256 sharesRatio)
        internal
        pure
        returns (Tokens, Shares, Shares, Tokens, Tokens)
    {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, sharesRatio);
        amount = Tokens.wrap(bound(Tokens.unwrap(amount), 0, Tokens.unwrap(fromBalance)));
        // If `amount == fromBalance`, then we would've executed the `amount`-less version instead,
        // the version with `All`
        assume(amount != fromBalance);
        return (totalSupply, totalShares, fromShares, fromBalance, amount);
    }

    function testTransferSome(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, sharesRatio);

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));
        Tokens toBalance = toShares.toTokens(totalSupply, totalShares);

        (Shares newFromShares, Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(amount, taxRate, totalSupply, totalShares, fromShares, toShares);
        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - (newFromShares + newToShares)),
            "shares delta"
        );

        Tokens newFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(amount, BASIS - taxRate));
        Tokens expectedNewToBalanceLo = toBalance + amount - castUp(scale(amount, taxRate));

        assertEq(Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "newFromBalance");
        // TODO: tighten these bounds to exact equality
        assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
        assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
    }

    function testTransferAll(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public pure virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, sharesRatio);

        // The only way that it's possible for an account to reach zero balance is by calling one of
        // the `All` variants, which explicitly zeroes the shares
        if (Tokens.unwrap(fromBalance) == 0) {
            assume(Shares.unwrap(fromShares) == 0);
        }

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));
        Tokens toBalance = toShares.toTokens(totalSupply, totalShares);

        (Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(taxRate, totalSupply, totalShares, fromShares, toShares);

        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - newToShares),
            "shares delta"
        );

        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);

        Tokens expectedNewToBalanceLo = toBalance + fromBalance - castUp(scale(fromBalance, taxRate));
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(fromBalance, BASIS - taxRate));
        if (newToShares == toShares) {
            assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
            assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
        } else {
            assertEq(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance");
        }
    }

    function testTransferSomeToWhale(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, sharesRatio);

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));

        (Shares newFromShares, Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(amount, taxRate, totalSupply, totalShares, fromShares, toShares);

        assume(newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR));

        Shares counterfactualToShares;
        (newFromShares, counterfactualToShares, newToShares, newTotalShares) =
            ReflectMath.getTransferSharesToWhale(amount, taxRate, totalSupply, totalShares, fromShares, toShares);

        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertEq(
            Shares.unwrap(newToShares),
            Shares.unwrap(newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE),
            "to shares whale limit"
        );
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - (newFromShares + newToShares)),
            "shares delta"
        );

        Tokens newFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens counterfactualToBalance = counterfactualToShares.toTokens(totalSupply, totalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;
        Tokens expectedCounterfactualToBalance = newToBalance - cast(scale(amount, BASIS - taxRate));

        assertEq(Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "newFromBalance");

        uint256 fudge = 1;
        assertGe(
            Tokens.unwrap(counterfactualToBalance) + fudge,
            Tokens.unwrap(expectedCounterfactualToBalance),
            "counterfactualToBalance lower"
        );
        assertLe(
            Tokens.unwrap(counterfactualToBalance),
            Tokens.unwrap(expectedCounterfactualToBalance) + fudge,
            "counterfactualToBalance upper"
        );
    }

    function testTransferAllToWhale(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, sharesRatio);

        // The only way that it's possible for an account to reach zero balance is by calling one of
        // the `All` variants, which explicitly zeroes the shares
        if (Tokens.unwrap(fromBalance) == 0) {
            assume(Shares.unwrap(fromShares) == 0);
        }

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        toShares =
            Shares.wrap(bound(Shares.unwrap(toShares), 0, Shares.unwrap(totalShares.div(Settings.ANTI_WHALE_DIVISOR))));

        (Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(taxRate, totalSupply, totalShares, fromShares, toShares);

        assume(newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR));

        Shares counterfactualToShares;
        (counterfactualToShares, newToShares, newTotalShares) =
            ReflectMath.getTransferSharesToWhale(taxRate, totalShares, fromShares, toShares);

        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(newToShares),
            Shares.unwrap(newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE),
            "to shares whale limit"
        );
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - newToShares),
            "shares delta"
        );

        Tokens newToBalance = newToShares.toTokens(totalSupply, newTotalShares);
        Tokens counterfactualToBalance = counterfactualToShares.toTokens(totalSupply, totalShares);

        Tokens expectedCounterfactualToBalanceLo = newToBalance - castUp(scale(fromBalance, BASIS - taxRate));
        Tokens expectedCounterfactualToBalanceHi = newToBalance - cast(scale(fromBalance, BASIS - taxRate));

        uint256 fudge = 1;
        assertGe(
            Tokens.unwrap(counterfactualToBalance) + fudge,
            Tokens.unwrap(expectedCounterfactualToBalanceLo),
            "counterfactualToBalance lower"
        );
        assertLe(
            Tokens.unwrap(counterfactualToBalance),
            Tokens.unwrap(expectedCounterfactualToBalanceHi) + fudge,
            "counterfactualToBalance upper"
        );
    }

    function testTransferFromPair(
        Tokens totalSupply,
        Shares totalShares,
        Shares toShares,
        Tokens amount,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public view virtual {
        Tokens toBalance;
        (totalSupply, totalShares, toShares, toBalance) = _boundCommon(totalSupply, totalShares, toShares, sharesRatio);
        amount = Tokens.wrap(
            bound(
                Tokens.unwrap(amount),
                1 wei,
                Tokens.unwrap(
                    Settings.INITIAL_SUPPLY - toBalance > totalSupply.div(Settings.ANTI_WHALE_DIVISOR)
                        ? totalSupply.div(Settings.ANTI_WHALE_DIVISOR)
                        : Settings.INITIAL_SUPPLY - toBalance
                ) - 1 wei
            )
        );

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        (Shares newToShares, Shares newTotalShares, Tokens newTotalSupply) =
            ReflectMath.getTransferSharesFromPair(taxRate, totalSupply, totalShares, amount, toShares);

        assertGe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares decreased");
        assertEq(Shares.unwrap(newTotalShares - totalShares), Shares.unwrap(newToShares - toShares), "shares delta");
        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");

        // This case is handled in the token by simply applying the whale limit
        assume(newToShares <= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE);

        Tokens newToBalance = newToShares.toTokens(newTotalSupply, newTotalShares);

        Tokens expectedNewToBalanceLo = toBalance + amount - castUp(scale(amount, taxRate));
        Tokens expectedNewToBalanceHi = toBalance + castUp(scale(amount, BASIS - taxRate));
        assertGe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceLo), "newToBalance lower");
        assertLe(Tokens.unwrap(newToBalance), Tokens.unwrap(expectedNewToBalanceHi), "newToBalance upper");
    }

    function testTransferSomeToPair(
        Tokens totalSupply,
        Shares totalShares,
        Shares fromShares,
        Tokens amount,
        BasisPoints taxRate,
        uint256 sharesRatio
    ) public view virtual {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, sharesRatio);

        taxRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(taxRate),
                    BasisPoints.unwrap(Settings.MIN_TAX),
                    BasisPoints.unwrap(Settings.MAX_TAX)
                )
            )
        );

        (Shares newFromShares, Shares newTotalShares,, Tokens newTotalSupply) =
            ReflectMath.getTransferSharesToPair(taxRate, totalSupply, totalShares, amount, fromShares);

        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(Shares.unwrap(totalShares - newTotalShares), Shares.unwrap(fromShares - newFromShares), "shares delta");

        Tokens newFromBalance = newFromShares.toTokens(newTotalSupply, newTotalShares);

        Tokens expectedNewFromBalance = fromBalance - amount;
        assertEq(Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "newFromBalance");
    }

    function testDeliver(Tokens totalSupply, Shares totalShares, Shares fromShares, Tokens amount, uint256 sharesRatio)
        public
        view
        virtual
    {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, sharesRatio);

        (Shares newFromShares, Shares newTotalShares) =
            ReflectMath.getDeliverShares(amount, totalSupply, totalShares, fromShares);

        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(Shares.unwrap(totalShares - newTotalShares), Shares.unwrap(fromShares - newFromShares), "shares delta");

        Tokens newFromBalance = newFromShares.toTokens(totalSupply, newTotalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;

        assertEq(
            Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "new balance, expected new balance"
        );
    }

    function testBurn(Tokens totalSupply, Shares totalShares, Shares fromShares, Tokens amount, uint256 sharesRatio)
        public
        view
        virtual
    {
        Tokens fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, sharesRatio);

        (Shares newFromShares, Shares newTotalShares, Tokens newTotalSupply) =
            ReflectMath.getBurnShares(amount, totalSupply, totalShares, fromShares);

        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(Shares.unwrap(totalShares - newTotalShares), Shares.unwrap(fromShares - newFromShares), "shares delta");

        Tokens newFromBalance = newFromShares.toTokens(newTotalSupply, newTotalShares);
        Tokens expectedNewFromBalance = fromBalance - amount;

        assertEq(
            Tokens.unwrap(newFromBalance), Tokens.unwrap(expectedNewFromBalance), "new balance, expected new balance"
        );
    }
}
