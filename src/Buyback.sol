// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TwoStepOwnable} from "./utils/TwoStepOwnable.sol";
import {Context} from "./utils/Context.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "./interfaces/IFU.sol";

import {IUniswapV2Pair, FastUniswapV2PairLib} from "./interfaces/IUniswapV2Pair.sol";
import {pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {BasisPoints, ZERO as ZERO_BP, BASIS, scaleUp} from "./types/BasisPoints.sol";

import {FastTransferLib} from "./lib/FastTransferLib.sol";
import {tmp, alloc} from "./lib/512Math.sol";
import {Math} from "./lib/Math.sol";
import {FastLogic} from "./lib/FastLogic.sol";
import {Ternary} from "./lib/Ternary.sol";

/// @custom:security non-reentrant
IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

BasisPoints constant UNIV2_FEE = BasisPoints.wrap(30);

library FastFu {
    error DeliverFailed();

    function fastDeliver(IFU fu, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x00, 0x3bd5d173) // selector for `deliver(uint256)`
            mstore(0x20, amount)

            if iszero(call(gas(), fu, 0x00, 0x1c, 0x24, 0x00, 0x20)) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            if iszero(or(and(eq(mload(0x00), 0x01), gt(returndatasize(), 0x1f)), iszero(returndatasize()))) {
                mstore(0x00, 0x9f70b2cd) // selector for `DeliverFailed()`
                revert(0x1c, 0x04)
            }
        }
    }
}

contract Buyback is TwoStepOwnable, Context {
    using FastTransferLib for IERC20;
    using FastTransferLib for IFU;
    using FastTransferLib for IUniswapV2Pair;
    using FastFu for IFU;
    using FastUniswapV2PairLib for IUniswapV2Pair;
    using Math for uint256;
    using FastLogic for bool;
    using Ternary for bool;

    /// @custom:security non-reentrant
    IFU public immutable token;
    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;

    uint120 public lastLpBalance;
    uint120 public kTarget;
    BasisPoints public ownerFee;

    // TODO: revisit these constants
    uint256 internal constant _TWAP_PERIOD = 1 days;
    uint256 internal constant _TWAP_PERIOD_TOLERANCE = 1 hours;

    uint256 internal priceCumulativeLast;
    uint32 internal blockTimestampLast;

    event OwnerFee(BasisPoints oldFee, BasisPoints newFee);
    event OracleConsultation(uint256 cumulativePrice);

    error FeeIncreased(BasisPoints oldFee, BasisPoints newFee);
    error FeeNotZero(BasisPoints ownerFee);

    error PriceTooStale(uint256 elapsed);
    error PriceTooFresh(uint256 elapsed);
    error PriceTooLow(uint256 actualQ112, uint256 expectedQ112);

    error TooMuchSlippage(uint256 actual, uint256 expected);

    constructor(bytes20 gitCommit, IFU token_, address initialOwner, BasisPoints ownerFee_) {
        require(_msgSender() == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        require(initialOwner != address(0));
        require(ownerFee_ < BASIS);

        emit IFU.GitCommit(gitCommit);

        _setOwner(initialOwner);
        token = token_;
        pair = pairFor(token, WETH);
        lastLpBalance = kTarget = uint120(IERC20(pair).fastBalanceOf(address(this)));
        ownerFee = ownerFee_;
        emit OwnerFee(BASIS, ownerFee);
    }

    function setFee(BasisPoints newOwnerFee) external onlyOwner returns (bool) {
        BasisPoints oldFee = ownerFee;
        if (newOwnerFee > oldFee) {
            revert FeeIncreased(oldFee, newOwnerFee);
        }
        ownerFee = newOwnerFee;
        emit OwnerFee(oldFee, newOwnerFee);
        return true;
    }

    function renounceOwnership() public override returns (bool) {
        if (ownerFee != ZERO_BP) {
            revert FeeNotZero(ownerFee);
        }
        return super.renounceOwnership();
    }

    function consult() external returns (bool) {
        unchecked {
            if (blockTimestampLast + (_TWAP_PERIOD + _TWAP_PERIOD_TOLERANCE) > block.timestamp) {
                revert PriceTooFresh(block.timestamp - blockTimestampLast);
            }
        }
        // TODO: use `<` instead of `>` by reversing all calls to `maybeSwap` in `buyback()`
        priceCumulativeLast = pair.fastPriceCumulativeLast(address(token) > address(WETH));
        emit OracleConsultation(priceCumulativeLast);
        // slither-disable-next-line unused-return
        (,, blockTimestampLast) = pair.getReserves();
    }

    function buyback(uint256 minOwnerFee) external returns (bool) {
        address owner_ = owner();
        BasisPoints ownerFee_ = ownerFee;

        // adjust `kTarget` to account for any extra LP tokens that may have been sent to the
        // `Buyback` contract since the last time `buyback()` was called
        uint256 lpBalance = pair.fastBalanceOf(address(this));
        uint256 kTarget_;
        unchecked {
            kTarget_ = kTarget * lpBalance / lastLpBalance;
        }

        // compute the underlying liquidity
        uint256 liquidity;
        unchecked {
            // slither-disable-next-line unused-return
            (uint256 reserve0, uint256 reserve1,) = pair.fastGetReserves();
            liquidity = (reserve0 * reserve1).sqrt();
        }

        // compute the amount of LP to be burned to (approximately) bring `k` back to the target
        // amount
        uint256 left;
        uint256 right;
        unchecked {
            left = lpBalance * liquidity;
            // slither-disable-next-line divide-before-multiply
            right = pair.fastTotalSupply() * kTarget_;
        }
        uint256 burnLp = (left - right) / liquidity;

        // burn LP tokens and receive some of the underlying tokens
        pair.fastTransfer(address(pair), burnLp);
        (uint256 amountWeth, uint256 amountFu) = pair.fastBurn(address(this));

        /// Now we have to compute the amount of WETH that is owable to `owner()`

        // get the reserves again. we have to get them _again_ because there may be excess tokens in
        // the pair before calling `burn`. calling `burn` implicitly synchronizes the pair with its
        // balances.
        bool sortTokens = (address(token) < address(WETH));
        (amountWeth, amountFu) = sortTokens.maybeSwap(amountWeth, amountFu);
        if ((owner_ == address(0)).or(ownerFee_ == ZERO_BP)) {
            amountWeth = WETH.fastBalanceOf(address(this));
        }
        uint256 feeWeth = scaleUp(amountWeth, ownerFee_);
        // slither-disable-next-line unused-return
        (uint256 reserveWeth, uint256 reserveFu,) = pair.fastGetReserves();
        (reserveWeth, reserveFu) = sortTokens.maybeSwap(reserveWeth, reserveFu);

        // consult the oracle
        if (_msgSender() != owner_) {
            uint256 elapsed = block.timestamp - blockTimestampLast;
            if (elapsed < _TWAP_PERIOD - _TWAP_PERIOD_TOLERANCE) {
                revert PriceTooFresh(elapsed);
            }
            if (elapsed > _TWAP_PERIOD + _TWAP_PERIOD_TOLERANCE) {
                revert PriceTooStale(elapsed);
            }
            // TODO: remove the following `!` by swapping every other call to `maybeSwap` in this function
            uint256 oraclePrice;
            unchecked {
                oraclePrice = uint224((pair.fastPriceCumulativeLast(!sortTokens) - priceCumulativeLast) / elapsed);
            }
            uint256 currentPrice = (reserveWeth << 112) / reserveFu;
            if (currentPrice < oraclePrice) {
                revert PriceTooLow(currentPrice, oraclePrice);
            }
        }

        // note that this calculation uses `amountFu`, which is the amount *SENT BY THE PAIR*, and
        // not the amount actually received by this contract (i.e. it is the amount before fees are
        // taken out)
        {
            uint256 feeFu = scaleUp(amountFu, ownerFee_);
            feeWeth += feeFu * reserveWeth / (reserveFu + feeFu);
        }

        // swap the leftover WETH to FU
        uint256 swapWethIn = amountWeth - feeWeth; // underflow indicates price too low relative to `ownerFee`
        uint256 swapFuOut;
        unchecked {
            uint256 swapWethWithFee = BasisPoints.unwrap(BASIS - UNIV2_FEE) * swapWethIn;
            uint256 n = swapWethWithFee * reserveFu;
            uint256 d = BasisPoints.unwrap(BASIS) * reserveWeth + swapWethWithFee;
            swapFuOut = n / d;
        }
        WETH.fastTransfer(address(pair), swapWethIn);
        {
            (uint256 amount0, uint256 amount1) = sortTokens.maybeSwap(0, swapFuOut);
            pair.fastSwap(amount0, amount1, address(this));
        }

        // the last step is to pay the WETH fee to the owner and to `deliver` the
        token.fastDeliver(token.fastBalanceOf(address(this)));
        uint256 actualOwnerFee = WETH.fastBalanceOf(address(this));
        if (actualOwnerFee < minOwnerFee) {
            revert TooMuchSlippage(actualOwnerFee, minOwnerFee);
        }
        WETH.fastTransfer(owner_, actualOwnerFee);

        // update state for next time, in case somebody sends LP tokens to this contract
        (kTarget, lastLpBalance) = (uint120(kTarget_), uint120(pair.fastBalanceOf(address(this))));

        return true;
    }
}
