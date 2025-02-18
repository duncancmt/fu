// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "@forge-std/Test.sol";
import {Buyback} from "src/Buyback.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {BasisPoints, BASIS} from "src/types/BasisPoints.sol";
import {FUDeploy, Common} from "./Deploy.t.sol";

import {StdCheats} from "@forge-std/StdCheats.sol";

contract BuybackTest is FUDeploy, Test {
    function wethBalanceSlot() internal view returns (bytes32) {
        return keccak256(abi.encode(fu.pair(), bytes32(uint256(3))));
    }

    function fuBalanceSlot() internal pure returns (bytes32) {
        return 0x00000000000000000000000000000000e086ec3a639808bbda893d5b4ac93601;
    }

    // --------------------------------------
    // Test: constructor correctness
    // --------------------------------------

    function testConstructor() public view {
        // The constructor sets:
        //   ownerFee = 50% (our chosen initialFee)
        //   lastLpBalance & kTarget to the pair's balanceOf(buyback)
        assertEq(buyback.ownerFee(), 5000, "ownerFee mismatch");
        assertEq(buyback.lastLpBalance(), 72057594037927935999998999, "lastLpBalance mismatch");
        assertEq(buyback.kTarget(), 72057594037927935999998999, "kTarget mismatch");
        assertEq(buyback.owner(), address(uint160(uint256(keccak256("Buyback owner")))), "owner mismatch");
        assertEq(buyback.pendingOwner(), address(0), "pending owner mismatch");
    }

    // --------------------------------------
    // Test: setFee
    // --------------------------------------

    function testSetFeeSuccess() public {
        // Only owner can set fee
        prank(buyback.owner());
        expectEmit(true, true, true, true, address(buyback));
        emit Buyback.OwnerFee(BasisPoints.wrap(5000), BasisPoints.wrap(500));
        buyback.setFee(BasisPoints.wrap(500)); // Lower from 10% to 5%
        assertEq(buyback.ownerFee(), 500, "ownerFee should be updated");
    }

    function testSetFeeRevertNonOwner() public {
        expectRevert(abi.encodeWithSignature("PermissionDenied()"));
        buyback.setFee(BasisPoints.wrap(500));
    }

    function testSetFeeRevertFeeIncreased() public {
        // Attempt to increase from 5000 -> 5001 should revert
        prank(buyback.owner());
        expectRevert(
            abi.encodeWithSelector(Buyback.FeeIncreased.selector, BasisPoints.wrap(5000), BasisPoints.wrap(5001))
        );
        buyback.setFee(BasisPoints.wrap(5001));
    }

    // --------------------------------------
    // Test: renounceOwnership
    // --------------------------------------

    function testRenounceOwnershipSuccessWhenFeeZero() public {
        // First set fee to zero
        prank(buyback.owner());
        buyback.setFee(BasisPoints.wrap(0));

        // Now renounce ownership
        prank(buyback.owner());
        bool success = buyback.renounceOwnership();
        assertTrue(success, "renounceOwnership() not successful");
        assertEq(buyback.owner(), address(0), "Owner not zeroed out");
        assertEq(buyback.pendingOwner(), address(0), "Pending owner not zeroed out");
    }

    function testRenounceOwnershipRevertFeeNotZero() public {
        // Our current fee is 50%. Trying to renounce must revert
        prank(buyback.owner());
        expectRevert(abi.encodeWithSelector(Buyback.FeeNotZero.selector, BasisPoints.wrap(5000)));
        buyback.renounceOwnership();
    }

    // --------------------------------------
    // Test: consult()
    // --------------------------------------

    function testConsultSuccess() public {
        assertEq(load(address(buyback), bytes32(uint256(3))), bytes32(0), "fu/weth cumulative not zero");
        assertEq(load(address(buyback), bytes32(uint256(4))), bytes32(0), "weth/fu cumulative not zero");
        assertEq(
            load(address(buyback), bytes32(uint256(5))),
            bytes32(uint256(deployTime)),
            "timestamp last not equal to deploy time"
        );

        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();
        // Advance time to ensure consult won't revert with "PriceTooFresh"
        warp(getBlockTimestamp() + elapsed);

        uint256 expectedFuWeth = (5 ether << 112) / (type(uint112).max / 5) * (EPOCH - deployTime + elapsed);
        uint256 expectedWethFu = (uint256(type(uint112).max / 5) << 112) / 5 ether * (EPOCH - deployTime + elapsed);

        // Expect event
        expectEmit(true, true, true, true, address(buyback));
        emit Buyback.OracleConsultation(address(this), expectedFuWeth, expectedWethFu);

        buyback.consult();

        assertEq(load(address(buyback), bytes32(uint256(3))), bytes32(expectedFuWeth), "fu/weth cumulative not zero");
        assertEq(load(address(buyback), bytes32(uint256(4))), bytes32(expectedWethFu), "weth/fu cumulative not zero");
        assertEq(load(address(buyback), bytes32(uint256(5))), bytes32(getBlockTimestamp()), "timestamp last not zero");
    }

    function testConsultRevertPriceTooFresh() public {
        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();

        // Let's do a first consult to set things up:
        warp(getBlockTimestamp() + elapsed);
        buyback.consult();

        // Now do a second consult too soon
        warp(getBlockTimestamp() + 10);
        expectRevert(
            abi.encodeWithSelector(
                Buyback.PriceTooFresh.selector,
                10 // (block.timestamp - timestampLast) in this scenario
            )
        );
        buyback.consult();
    }

    // --------------------------------------
    // Test: buyback()
    // --------------------------------------

    function testBuybackSuccess() public {
        // Step 0: Sanity checks
        IUniswapV2Pair pair = IUniswapV2Pair(fu.pair());
        uint256 pairWethBalance = WETH.balanceOf(address(pair));
        uint256 kTarget = buyback.kTarget();
        assertEq(kTarget, pair.balanceOf(address(buyback)));
        assertEq(kTarget, buyback.lastLpBalance());
        address owner = buyback.owner();
        assertEq(WETH.balanceOf(owner), 0);
        uint256 percentIncrease = 1;

        // Step 1: Increase the liquidity
        store(
            address(WETH),
            wethBalanceSlot(),
            bytes32(uint256(load(address(WETH), wethBalanceSlot())) * (percentIncrease + 100) / 100)
        );
        store(
            address(fu),
            fuBalanceSlot(),
            bytes32(uint256(load(address(fu), fuBalanceSlot())) * (percentIncrease + 100) / 100)
        );
        pair.sync();

        // Step 1: Consult the oracle and store the cumulatives
        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();
        warp(getBlockTimestamp() + elapsed);
        buyback.consult();

        // Step 3: Mature the oracle price
        warp(getBlockTimestamp() + elapsed);

        // Step 4: Decrease the price slightly so that we pass the WETH/FU price check
        store(address(fu), fuBalanceSlot(), bytes32(uint256(load(address(fu), fuBalanceSlot())) * 10001 / 10000));

        // Step 5: Check events

        // buyback burns LP tokens
        expectEmit(true, true, true, false, address(pair));
        emit IERC20.Transfer(address(buyback), address(pair), type(uint256).max);
        expectEmit(true, true, true, false, address(pair));
        emit IERC20.Transfer(address(pair), address(0), type(uint256).max);

        // pair transfers underlying tokens to buyback
        if (address(WETH) < address(fu)) {
            expectEmit(true, true, true, false, address(WETH));
            emit IERC20.Transfer(address(pair), address(buyback), type(uint256).max);
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(address(pair), address(buyback), type(uint256).max);
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(address(pair), address(0), type(uint256).max);
        } else {
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(address(pair), address(buyback), type(uint256).max);
            expectEmit(true, true, true, false, address(fu));
            emit IERC20.Transfer(address(pair), address(0), type(uint256).max);
            expectEmit(true, true, true, false, address(WETH));
            emit IERC20.Transfer(address(pair), address(buyback), type(uint256).max);
        }

        // buyback transfers WETH to pair
        expectEmit(true, true, true, false, address(WETH));
        emit IERC20.Transfer(address(buyback), address(pair), type(uint256).max);

        // pair transfers FU to buyback
        expectEmit(true, true, true, false, address(fu));
        emit IERC20.Transfer(address(pair), address(buyback), type(uint256).max);
        expectEmit(true, true, true, false, address(fu));
        emit IERC20.Transfer(address(pair), address(0), type(uint256).max);

        // buyback burns FU
        expectEmit(true, true, true, false, address(fu));
        emit IERC20.Transfer(address(buyback), address(0), type(uint256).max);
        // buyback transfers WETH to owner
        expectEmit(true, true, true, false, address(WETH));
        emit IERC20.Transfer(address(buyback), owner, type(uint256).max);

        // Step 6: Do the actual buyback
        expectEmit(true, true, true, true, address(buyback));
        emit Buyback.Buyback(address(this), kTarget);
        assertTrue(buyback.buyback(), "buyback() should not revert");

        assertEq(buyback.kTarget(), kTarget);
        assertLt(buyback.lastLpBalance(), kTarget);
        assertEq(buyback.lastLpBalance(), pair.balanceOf(address(buyback)));

        (uint256 reserves0, uint256 reserves1, uint256 timestampLast) = pair.getReserves();
        if (address(WETH) < address(fu)) {
            assertEq(reserves0, WETH.balanceOf(address(pair)));
            assertEq(reserves1, fu.balanceOf(address(pair)));
        } else {
            assertEq(reserves0, fu.balanceOf(address(pair)));
            assertEq(reserves1, WETH.balanceOf(address(pair)));
        }
        assertEq(timestampLast, getBlockTimestamp());

        uint256 priceImpactToleranceBp = 30;
        uint256 expectedOwnerFees = pairWethBalance * percentIncrease / 100;
        assertGe(WETH.balanceOf(owner), expectedOwnerFees * (10000 - priceImpactToleranceBp) / 10000);

        assertEq(WETH.balanceOf(address(buyback)), 0);
        assertEq(fu.balanceOf(address(buyback)), 0);
    }

    function testBuybackRevertPriceTooFresh() public {
        // Must do a consult, but we do it too recently to cause revert in buyback
        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();
        warp(getBlockTimestamp() + elapsed);
        buyback.consult();

        // Increase liquidity so that there's some LP tokens to burn
        store(
            address(WETH), wethBalanceSlot(), bytes32(uint256(load(address(WETH), wethBalanceSlot())) * 10001 / 10000)
        );
        store(address(fu), fuBalanceSlot(), bytes32(uint256(load(address(fu), fuBalanceSlot())) * 10001 / 10000));
        IUniswapV2Pair(fu.pair()).sync();

        // Now buyback should revert with PriceTooFresh, because not enough time has elapsed
        expectRevert(abi.encodeWithSelector(Buyback.PriceTooFresh.selector, 0));
        buyback.buyback();
    }

    function testBuybackRevertPriceTooStale() public {
        // Do a consult
        buyback.consult();

        // Increase liquidity so that there's some LP tokens to burn
        store(
            address(WETH), wethBalanceSlot(), bytes32(uint256(load(address(WETH), wethBalanceSlot())) * 10001 / 10000)
        );
        store(address(fu), fuBalanceSlot(), bytes32(uint256(load(address(fu), fuBalanceSlot())) * 10001 / 10000));
        IUniswapV2Pair(fu.pair()).sync();

        // Warp beyond (TWAP_PERIOD + TOLERANCE) to cause PriceTooStale
        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();
        warp(getBlockTimestamp() + elapsed + 1);

        expectRevert(abi.encodeWithSelector(Buyback.PriceTooStale.selector, elapsed + 1));
        buyback.buyback();
    }

    function testBuybackRevertPriceTooLow() public {
        // Do a consult
        buyback.consult();

        // Increase liquidity so that there's some LP tokens to burn
        store(
            address(WETH), wethBalanceSlot(), bytes32(uint256(load(address(WETH), wethBalanceSlot())) * 10001 / 10000)
        );
        store(address(fu), fuBalanceSlot(), bytes32(uint256(load(address(fu), fuBalanceSlot())) * 10001 / 10000));
        IUniswapV2Pair(fu.pair()).sync();

        // Warp so that the oracle has matured
        uint256 elapsed = buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE();
        warp(getBlockTimestamp() + elapsed);

        (bool success, bytes memory reason) = address(buyback).call(abi.encodeCall(buyback.buyback, ()));
        assertFalse(success);
        assertEq(bytes4(reason), Buyback.PriceTooLow.selector);
    }

    // Solidity inheritance is dumb
    function deal(address who, uint256 value) internal virtual override(Common, StdCheats) {
        return super.deal(who, value);
    }
}
