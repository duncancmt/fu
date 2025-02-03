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

    event OwnerFee(BasisPoints oldFee, BasisPoints newFee);

    error FeeIncreased(BasisPoints oldFee, BasisPoints newFee);
    error FeeNotZero(BasisPoints ownerFee);

    constructor(bytes20 gitCommit, IFU token_, address initialOwner, BasisPoints ownerFee_) {
        require(_msgSender() == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        require(initialOwner != address(0));
        require(ownerFee_ < BASIS);

        emit IFU.GitCommit(gitCommit);

        _setPendingOwner(initialOwner);
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

    function buyback() external returns (bool) {
        // `buyback()` can't be called if `owner()` is unset
        address owner_ = owner();
        BasisPoints ownerFee_ = ownerFee;
        require((owner_ != address(0)).or(ownerFee == ZERO_BP));

        // adjust `kTarget` to account for any extra LP tokens that may have been sent to the
        // `Buyback` contract since the last time `buyback()` was called
        uint256 lpBalance = pair.fastBalanceOf(address(this));
        uint256 kTarget_;
        unchecked {
            kTarget_ = kTarget * lpBalance / lastLpBalance;
        }
        kTarget = uint120(kTarget_);

        // compute the underlying liquidity
        uint256 liquidity;
        unchecked {
            (uint256 reserve0, uint256 reserve1,) = pair.fastGetReserves();
            liquidity = (reserve0 * reserve1).sqrt();
        }

        // compute the amount of LP to be burned to (approximately) bring `k` back to the target
        // amount
        uint256 left;
        uint256 right;
        unchecked {
            left = lpBalance * liquidity;
            right = pair.fastTotalSupply() * kTarget_;
        }
        uint256 burnLp = (left - right) / liquidity;

        pair.fastTransfer(address(pair), burnLp);
        (uint256 amountWeth, uint256 amountFu) = pair.fastBurn(address(this));
        bool sortTokens = (address(token) < address(WETH));
        (amountWeth, amountFu) = sortTokens.swap(amountWeth, amountFu);
        uint256 feeWeth = scaleUp(amountWeth, ownerFee_);
        (uint256 reserveWeth, uint256 reserveFu,) = pair.fastGetReserves();
        (reserveWeth, reserveFu) = sortTokens.swap(reserveWeth, reserveFu);
        {
            uint256 feeFu = scaleUp(amountFu, ownerFee_);
            feeWeth += feeFu * reserveWeth / (reserveFu + feeFu);
        }
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
            (uint256 amount0, uint256 amount1) = sortTokens.swap(0, swapFuOut);
            pair.fastSwap(amount0, amount1, address(this));
        }

        lastLpBalance = uint120(pair.fastBalanceOf(address(this)));
        token.fastDeliver(token.fastBalanceOf(address(this)));
        WETH.fastTransfer(owner_, WETH.fastBalanceOf(address(this)));
        return true;
    }
}
