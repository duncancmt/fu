// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "@forge-std/Test.sol";
import {Buyback} from "src/Buyback.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {BasisPoints, BASIS} from "src/types/BasisPoints.sol";
import {FUDeploy} from "./Deploy.t.sol";

contract BuybackTest is FUDeploy {
    // Some helpful constants
    BasisPoints public constant ZERO_BP = BasisPoints.wrap(0);
    BasisPoints public constant THIRTY_BP = BasisPoints.wrap(30);

    // --------------------------------------
    // Test: constructor correctness
    // --------------------------------------

    function testConstructor() public {
        // The constructor sets:
        //   ownerFee = 50% (our chosen initialFee)
        //   lastLpBalance & kTarget to the pair's balanceOf(buyback)

        //using assertEq() here is causing inheritance clashes with the same function defined in `Common` and `Test`. Not sure if you care to fix.
        require(BasisPoints.unwrap(buyback.ownerFee()) == 5000, "ownerFee mismatch");
        require(buyback.lastLpBalance() == 72057594037927935999998999, "lastLpBalance mismatch");
        require(buyback.kTarget() == 72057594037927935999998999, "kTarget mismatch");
        require(buyback.owner() == address(uint160(uint256(keccak256("Buyback owner")))), "owner mismatch");
        require(buyback.pendingOwner() == address(0), "pending owner mismatch");
    }

    /*

    // --------------------------------------
    // Test: setFee
    // --------------------------------------

    function testSetFeeSuccess() public {
        // Only owner can set fee
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit OwnerFee(BasisPoints.wrap(1000), BasisPoints.wrap(500));
        buyback.setFee(BasisPoints.wrap(500)); // Lower from 10% to 5%
        assertEq(BasisPoints.unwrap(buyback.ownerFee()), 500, "ownerFee should be updated");
    }

    function testSetFeeRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        buyback.setFee(BasisPoints.wrap(500));
    }

    function testSetFeeRevertFeeIncreased() public {
        // Attempt to increase from 1000 -> 2000 should revert
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Buyback.FeeIncreased.selector,
                BasisPoints.wrap(1000),
                BasisPoints.wrap(2000)
            )
        );
        buyback.setFee(BasisPoints.wrap(2000));
    }

    // --------------------------------------
    // Test: renounceOwnership
    // --------------------------------------
    function testRenounceOwnershipSuccessWhenFeeZero() public {
        // First set fee to zero
        vm.prank(OWNER);
        buyback.setFee(ZERO_BP);

        // Now renounce ownership
        vm.prank(OWNER);
        bool success = buyback.renounceOwnership();
        assertTrue(success, "renounceOwnership() not successful");
        assertEq(buyback.owner(), address(0), "Owner not zeroed out");
    }

    function testRenounceOwnershipRevertFeeNotZero() public {
        // Our current fee is 10%. Trying to renounce must revert
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Buyback.FeeNotZero.selector,
                BasisPoints.wrap(1000)
            )
        );
        buyback.renounceOwnership();
    }

    // --------------------------------------
    // Test: consult()
    // --------------------------------------
    function testConsultSuccess() public {
        // Advance time to ensure consult won't revert with "PriceTooFresh"
        vm.warp(block.timestamp + buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit OracleConsultation(
            address(this),
            0, // We can't easily predict the exact cumulative in a simple mock
            0
        );

        buyback.consult();
        // After consult, we can check that `timestampLast` was updated
        // But we'd need to read it from the contract's storage.
        // For brevity, we won't do a direct SLOAD; you can add an accessor or read via cheatcodes.
    }

    function testConsultRevertPriceTooFresh() public {
        // consult() requires that the last consult was older than (TWAP_PERIOD + TOLERANCE).
        // Right after deployment, `timestampLast` is 0. But it only sets when we do the first consult.
        // This is an edge condition. Typically you'd do a first consult, then a second one too soon.
        
        // Let's do a first consult to set things up:
        vm.warp(block.timestamp + buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 10);
        buyback.consult();

        // Now do a second consult too soon
        vm.warp(block.timestamp + 10);
        vm.expectRevert(
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
        // Step 1: Let us do a consult with correct timing first
        // Must warp forward enough that consult doesn't revert with PriceTooFresh
        // but not so far that it triggers PriceTooStale
        vm.warp(block.timestamp + buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 1);
        buyback.consult();

        // Step 2: Set pair's reserves so we pass the price checks
        // We set them in setUp, but let's reaffirm:
        // (reserveFu=1,000,000, reserveWeth=10,000)
        // We'll just keep them as is. It's consistent with a ratio that won't revert.
        // Step 3: Let's put some WETH into the buyback contract to simulate having it after burn
        // Actually the buyback gets WETH from the burn, which we mock in the pair. 
        // The pair's `fastBurn` returns 1000 FU and 10 WETH for example.

        // We also want to ensure the ratio from the TWAP is not artificially low
        // So we might set mockPair's cumulative price:
        // The code uses (reserveFu << 112) / reserveWeth for a check and also subtracts fastPriceCumulativeLast.
        // We'll just keep it simple and rely on the big "2**112 * 1000" number we used above.

        // Step 4: Do the actual buyback
        vm.expectEmit(true, true, true, true);
        emit Buyback(address(this), buyback.kTarget()); // check the event
        bool ok = buyback.buyback();
        assertTrue(ok, "buyback() should not revert");

        // Check that the new lastLpBalance and kTarget are updated
        // Note: buyback sets:
        //   (kTarget, lastLpBalance) = (uint120(kTarget_), uint120(pairBalance))
        // We can check them with public getters
        uint120 newKTarget = buyback.kTarget();
        uint120 newLastLpBalance = buyback.lastLpBalance();
        // newKTarget is scaled from old kTarget by ratio of new LP to old, in code. 
        // Because we are mocking the burn, the result might differ from a real scenario. 
        // We'll just check that they changed in some way:
        assertTrue(newKTarget != 1000, "kTarget was not updated");
        assertTrue(newLastLpBalance != 1000, "lastLpBalance was not updated");

        // Also check that the contract's WETH was transferred to the owner
        // The entire leftover WETH after fees & the swap is sent to `owner()`
        // We can't trivially know the exact final WETH amount. We'll just check > 0.
        uint256 ownerWethBal = mockWETH.balanceOf_(OWNER);
        assertTrue(ownerWethBal > 0, "Owner did not receive WETH fee");
    }

    function testBuybackRevertPriceTooFresh() public {
        // Must do a consult, but we do it too recently to cause revert in buyback
        vm.warp(block.timestamp + 10);
        buyback.consult();

        // Now buyback should revert with PriceTooFresh, because not enough time has elapsed
        vm.expectRevert(
            abi.encodeWithSelector(
                Buyback.PriceTooFresh.selector,
                0 // or 10 or so.  The code uses `block.timestamp - timestampLast`.
            )
        );
        buyback.buyback();
    }

    function testBuybackRevertPriceTooStale() public {
        // Do a consult at time T
        vm.warp(block.timestamp + 10);
        buyback.consult();

        // Warp far beyond (TWAP_PERIOD + TOLERANCE) to cause PriceTooStale
        vm.warp(block.timestamp + buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 1000);

        vm.expectRevert(
            abi.encodeWithSelector(
                Buyback.PriceTooStale.selector,
                buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 1000 - 10
            )
        );
        buyback.buyback();
    }

    function testBuybackRevertPriceTooLow() public {
        // We'll manipulate the mock so that the price is artificially high in the cumulative
        // but the *actual* ratio is very low, causing revert. 
        // Step 1: consult with correct timing
        vm.warp(block.timestamp + buyback.TWAP_PERIOD() + buyback.TWAP_PERIOD_TOLERANCE() + 1);
        buyback.consult();

        // Step 2: set reserves extremely unbalanced so that `(reserveFu << 112) / reserveWeth`
        // is far lower than the "overestimated" cumulative price
        mockPair.setReserves(10_000, 999_999_999, uint32(block.timestamp)); // Very small FU vs. big WETH

        vm.expectRevert(Buyback.PriceTooLow.selector);
        buyback.buyback();
    }

    // Events for reference (to match in expectEmit)
    event OwnerFee(BasisPoints oldFee, BasisPoints newFee);
    event OracleConsultation(address indexed keeper, uint256 cumulativeFuWeth, uint256 cumulativeWethFu);
    event Buyback(address indexed caller, uint256 kTarget);

    */
}


