// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Settings} from "src/core/Settings.sol";
import {ReflectMath} from "src/core/ReflectMath.sol";

import {BasisPoints, BASIS} from "src/core/types/BasisPoints.sol";
import {Shares} from "src/core/types/Shares.sol";
import {Balance} from "src/core/types/Balance.sol";
import {BalanceXShares, tmp, alloc, SharesToBalance} from "src/core/types/BalanceXShares.sol";
import {BalanceXBasisPoints, scale, cast, castUp} from "src/core/types/BalanceXBasisPoints.sol";

import {UnsafeMath} from "src/lib/UnsafeMath.sol";

import {Test} from "@forge-std/Test.sol";

import {console} from "@forge-std/console.sol";

contract ReflectMathTest is Test {
    using UnsafeMath for uint256;
    using SharesToBalance for Shares;

    function _oneTokenInShares(Balance totalSupply, Shares totalShares) internal pure returns (Shares) {
        BalanceXShares tmp1 = alloc().omul(Balance.wrap(10 ** Settings.DECIMALS), totalShares);
        Shares oneTokenInShares = tmp1.div(totalSupply);
        oneTokenInShares = oneTokenInShares.inc(tmp().omul(oneTokenInShares, totalSupply) < tmp1);
        assertTrue(tmp().omul(oneTokenInShares, totalSupply) >= tmp1);
        return oneTokenInShares;
    }

    function _boundCommon(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        uint256 sharesRatio
    ) internal pure returns (Balance, Shares, Shares, Balance) {
        totalSupply = Balance.wrap(
            bound(Balance.unwrap(totalSupply), 10 ** Settings.DECIMALS + 1, Balance.unwrap(Settings.INITIAL_SUPPLY))
        );
        //sharesRatio = bound(sharesRatio, Settings.MIN_SHARES_RATIO, Settings.INITIAL_SHARES_RATIO);
        sharesRatio = Settings.MIN_SHARES_RATIO; // TODO: remove
        Shares maxShares = Shares.wrap(Balance.unwrap(totalSupply) * (sharesRatio + 1) - 1);
        maxShares = maxShares > Settings.INITIAL_SHARES ? Settings.INITIAL_SHARES : maxShares;
        totalShares = Shares.wrap(
            bound(Shares.unwrap(totalShares), Balance.unwrap(totalSupply) * sharesRatio, Shares.unwrap(maxShares))
        );

        Shares oneTokenInShares = _oneTokenInShares(totalSupply, totalShares);
        Shares oneWeiInShares = Shares.wrap(Shares.unwrap(totalShares) / Balance.unwrap(totalSupply));
        oneWeiInShares =
            oneWeiInShares.inc(Shares.unwrap(oneWeiInShares) * Balance.unwrap(totalSupply) < Shares.unwrap(totalShares));

        vm.assume(oneWeiInShares < totalShares - oneTokenInShares); // only possible in extreme conditions due to rounding error
        fromShares = Shares.wrap(
            bound(
                Shares.unwrap(fromShares), Shares.unwrap(oneWeiInShares), Shares.unwrap(totalShares - oneTokenInShares)
            )
        );

        Balance fromBalance = fromShares.toBalance(totalSupply, totalShares);
        assertGt(Balance.unwrap(fromBalance), 0);
        return (totalSupply, totalShares, fromShares, fromBalance);
    }

    function _boundCommon(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Balance amount,
        uint256 sharesRatio
    ) internal pure returns (Balance, Shares, Shares, Balance, Balance) {
        Balance fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) = _boundCommon(totalSupply, totalShares, fromShares, sharesRatio);
        amount = Balance.wrap(bound(Balance.unwrap(amount), 1, Balance.unwrap(fromBalance)));
        return (totalSupply, totalShares, fromShares, fromBalance, amount);
    }

    function testTransfer(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        Balance amount,
        BasisPoints feeRate/*,
        uint256 sharesRatio*/
    ) external view {
        Balance fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, /* sharesRatio */ 0);

        feeRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(feeRate),
                    BasisPoints.unwrap(Settings.MIN_FEE),
                    BasisPoints.unwrap(Settings.MAX_FEE)
                )
            )
        );

        toShares = Shares.wrap(
            bound(
                Shares.unwrap(toShares),
                0,
                Shares.unwrap(totalShares - _oneTokenInShares(totalSupply, totalShares) - fromShares)
            )
        );
        vm.assume(fromShares + toShares < totalShares.div(2));
        Balance toBalance = toShares.toBalance(totalSupply, totalShares);

        // console.log("===");
        // console.log("totalSupply", totalSupply);
        // console.log("feeRate    ", feeRate);
        // console.log("amount     ", amount);
        // console.log("===");
        // console.log("fromBalance", fromBalance);
        // console.log("toBalance  ", toBalance);
        // console.log("===");
        (Shares newFromShares, Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(amount, feeRate, totalSupply, totalShares, fromShares, toShares);
        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares), "from shares increased");
        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - (newFromShares + newToShares)),
            "shares delta"
        );

        Balance newFromBalance = newFromShares.toBalance(totalSupply, newTotalShares);
        Balance newToBalance = newToShares.toBalance(totalSupply, newTotalShares);
        Balance expectedNewFromBalance = fromBalance - amount;
        Balance expectedNewToBalanceHi = toBalance + castUp(scale(amount, BASIS - feeRate));
        Balance expectedNewToBalanceLo = toBalance + amount - castUp(scale(amount, feeRate));

        assertEq(Balance.unwrap(newFromBalance), Balance.unwrap(expectedNewFromBalance), "newFromBalance");
        // TODO: tighten these bounds to exact equality
        assertGe(Balance.unwrap(newToBalance), Balance.unwrap(expectedNewToBalanceLo), "newToBalance lower");
        assertLe(Balance.unwrap(newToBalance), Balance.unwrap(expectedNewToBalanceHi), "newToBalance upper");
    }

    function testTransferAll(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Shares toShares,
        BasisPoints feeRate/*,
        uint256 sharesRatio*/
    ) external view {
        Balance fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance) =
            _boundCommon(totalSupply, totalShares, fromShares, /* sharesRatio */ 0);
        feeRate = BasisPoints.wrap(
            uint16(
                bound(
                    BasisPoints.unwrap(feeRate),
                    BasisPoints.unwrap(Settings.MIN_FEE),
                    BasisPoints.unwrap(Settings.MAX_FEE)
                )
            )
        );

        toShares = Shares.wrap(
            bound(
                Shares.unwrap(toShares),
                0,
                Shares.unwrap(totalShares - _oneTokenInShares(totalSupply, totalShares) - fromShares)
            )
        );
        vm.assume(fromShares + toShares < totalShares.div(2));
        Balance toBalance = toShares.toBalance(totalSupply, totalShares);

        (Shares newToShares, Shares newTotalShares) =
            ReflectMath.getTransferShares(feeRate, totalSupply, totalShares, fromShares, toShares);

        assertGe(Shares.unwrap(newToShares), Shares.unwrap(toShares), "to shares decreased");
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares), "total shares increased");
        assertEq(
            Shares.unwrap(totalShares - newTotalShares),
            Shares.unwrap(fromShares + toShares - newToShares),
            "shares delta"
        );

        Balance newToBalance = newToShares.toBalance(totalSupply, newTotalShares);
        // TODO: tighter bounds
        Balance expectedNewToBalanceLo = toBalance + fromBalance - castUp(scale(fromBalance, feeRate));
        Balance expectedNewToBalanceHi = toBalance + castUp(scale(fromBalance, BASIS - feeRate));
        assertGe(Balance.unwrap(newToBalance) + 1, Balance.unwrap(expectedNewToBalanceLo), "newToBalance lower");
        assertLe(Balance.unwrap(newToBalance), Balance.unwrap(expectedNewToBalanceHi) + 1, "newToBalance upper");
    }

    function testDeliver(
        Balance totalSupply,
        Shares totalShares,
        Shares fromShares,
        Balance amount/*,
        uint256 sharesRatio*/
    ) external view {
        Balance fromBalance;
        (totalSupply, totalShares, fromShares, fromBalance, amount) =
            _boundCommon(totalSupply, totalShares, fromShares, amount, /* sharesRatio */ 0);
        vm.assume(fromShares < totalShares.div(2));

        (Shares newFromShares, Shares newTotalShares) =
            ReflectMath.getDeliverShares(amount, totalSupply, totalShares, fromShares);
        assertLe(Shares.unwrap(newFromShares), Shares.unwrap(fromShares));
        assertLe(Shares.unwrap(newTotalShares), Shares.unwrap(totalShares));

        Balance newFromBalance = newFromShares.toBalance(totalSupply, newTotalShares);
        Balance expectedNewFromBalance = fromBalance - amount;

        assertEq(
            Balance.unwrap(newFromBalance), Balance.unwrap(expectedNewFromBalance), "new balance, expected new balance"
        );
    }
}
