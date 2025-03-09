// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "./interfaces/IFU.sol";
import {IUniswapV2Pair, FastUniswapV2PairLib} from "./interfaces/IUniswapV2Pair.sol";

import {MultiCallContext} from "./utils/MultiCallContext.sol";
import {Settings} from "./core/Settings.sol";
import {MoonPhase} from "./core/MoonPhase.sol";

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";

import {Panic} from "./lib/Panic.sol";
import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {FastTransferLib} from "./lib/FastTransferLib.sol";

/// @custom:security non-reentrant
IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
IFU constant FU = IFU(0xaC03C1Efc03A62A4C86c544161E2103E9B90D6f9);
IUniswapV2Pair constant PAIR = IUniswapV2Pair(0x00000000f70EE43829BaDaD0e2e7fBa8f88efFe3);

function tax() view returns (uint256) {
    return BasisPoints.unwrap(MoonPhase.moonPhase(block.timestamp));
}

function fastWithdraw(IERC20 weth, uint256 wad) {
    assembly ("memory-safe") {
        mstore(0x00, 0x2e1a7d4d) // selector for `withdraw(uint256)`
        mstore(0x20, wad)
        if iszero(call(gas(), weth, 0x00, 0x1c, 0x24, 0x00, 0x00)) {
            let ptr := mload(0x40)
            returndatacopy(ptr, 0x00, returndatasize())
            revert(ptr, returndatasize())
        }
    }
}

function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) {
    assembly ("memory-safe") {
        let ptr := mload(0x40) // Cache the free memory pointer.

        mstore(0x60, amount) // Store the `amount` argument.
        mstore(0x40, to) // Store the `to` argument.
        mstore(0x2c, shl(0x60, from)) // Store the `from` argument. (Clears `to`'s padding.)
        mstore(0x0c, 0x23b872dd000000000000000000000000) // Selector for `transferFrom(address,address,uint256)`, with `from`'s padding.

        // Calldata starts at offset 28 (32 - 4) [0x1f] and is 100 (3 * 32 + 4) [0x64] bytes long.
        // If there is returndata (optional) we copy the first 32 bytes into the first slot of memory.
        if iszero(call(gas(), token, 0x00, 0x1c, 0x64, 0x00, 0x20)) {
            returndatacopy(ptr, 0x00, returndatasize())
            revert(ptr, returndatasize())
        }
        // We check that the call either returned exactly 1 [true] (can't just be non-zero
        // data), or had no return data.
        if iszero(or(and(eq(mload(0x00), 0x01), lt(0x1f, returndatasize())), iszero(returndatasize()))) {
            mstore(0x00, 0x7939f424) // Selector for `TransferFromFailed()`
            revert(0x1c, 0x04)
        }

        mstore(0x60, 0x00) // Restore the zero slot to zero.
        mstore(0x40, ptr) // Restore the free memory pointer.
    }
}

contract Router is MultiCallContext {
    using UnsafeMath for uint256;
    using FastTransferLib for IERC20;
    using FastTransferLib for address payable;
    using FastUniswapV2PairLib for IUniswapV2Pair;
    using {fastWithdraw} for IERC20;
    using {safeTransferFrom} for IFU;

    error TooMuchSlippage(IERC20 token, uint256 actual, uint256 expected);

    uint256 internal constant _BASIS = BasisPoints.unwrap(BASIS);
    uint256 internal constant _UNISWAPV2_FEE_BP = 30;

    // TODO: review under-/over-flow conditions

    function _computeBuyExactOut(address recipient, uint256 fuOut) internal view returns (uint256 fuOutPair, uint256 ethIn) {
        uint256 scale = uint160(recipient) >> Settings.ADDRESS_SHIFT;
        if (scale == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        unchecked {
            fuOutPair = (fuOut * _BASIS).unsafeDivUp(_BASIS - tax());
            fuOutPair = (fuOutPair * Settings.CRAZY_BALANCE_BASIS).unsafeDivUp(scale).unsafeDivUp(Settings.CRAZY_BALANCE_BASIS);
            //fuOutPair++;
        }
        (uint256 reserveFu, uint256 reserveEth, ) = PAIR.fastGetReserves();

        unchecked {
            ethIn = (reserveEth * fuOutPair * _BASIS).unsafeDivUp((reserveFu - fuOutPair) * (_BASIS - _UNISWAPV2_FEE_BP)) + 1 wei;
        }
    }

    function quoteBuyExactOut(address recipient, uint256 fuOut) external view returns (uint256 ethIn) {
        (, ethIn) = _computeBuyExactOut(recipient, fuOut);
    }

    function _computeBuyExactIn(address recipient, uint256 ethIn) internal view returns (uint256 fuOutPair, uint256 fuOut) {
        uint256 scale = uint160(recipient) >> Settings.ADDRESS_SHIFT;
        if (scale == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        (uint256 reserveFu, uint256 reserveEth, ) = PAIR.fastGetReserves();
        unchecked {
            uint256 ethInWithFee = ethIn * (_BASIS - _UNISWAPV2_FEE_BP);
            fuOutPair = ethInWithFee * reserveFu / (reserveEth * _BASIS + ethInWithFee);
        }

        unchecked {
            fuOut = (fuOutPair * (_BASIS - tax())) / _BASIS * scale - 1;
        }
    }

    function quoteBuyExactIn(address recipient, uint256 ethIn) external view returns (uint256 fuOut) {
        (, fuOut) = _computeBuyExactIn(recipient, ethIn);
    }

    function _computeSellExactOut(address sender, uint256 ethOut) internal view returns (uint256 fuInPair, uint256 fuIn) {
        uint256 scale = uint160(sender) >> Settings.ADDRESS_SHIFT;
        if (scale == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        (uint256 reserveFu, uint256 reserveEth, ) = PAIR.fastGetReserves();
        unchecked {
            fuInPair = (reserveFu * ethOut * _BASIS).unsafeDivUp((reserveEth - ethOut) * (_BASIS - _UNISWAPV2_FEE_BP)) + 1;
        }

        unchecked {
            fuIn = (fuInPair * _BASIS).unsafeDivUp(_BASIS - tax()) * scale + 1;
        }
    }

    function quoteSellExactOut(address sender, uint256 ethOut) external view returns (uint256 fuIn) {
        (, fuIn) = _computeSellExactOut(sender, ethOut);
    }

    function _computeSellExactIn(address sender, uint256 fuIn) internal view returns (uint256 fuInPair, uint256 ethOut) {
        uint256 scale = uint160(sender) >> Settings.ADDRESS_SHIFT;
        if (scale == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        unchecked {
            fuInPair = (fuIn * Settings.CRAZY_BALANCE_BASIS).unsafeDiv(scale).unsafeDiv(Settings.CRAZY_BALANCE_BASIS);
            fuInPair = (fuInPair * (_BASIS - tax())).unsafeDiv(_BASIS);
            //fuInPair--;
        }

        (uint256 reserveFu, uint256 reserveEth, ) = PAIR.fastGetReserves();
        unchecked {
            uint256 fuInWithFee = fuInPair * (_BASIS - _UNISWAPV2_FEE_BP);
            ethOut = fuInWithFee * reserveEth / (reserveFu * _BASIS + fuInWithFee);
        }
    }

    function quoteSellExactIn(address sender, uint256 fuIn) external view returns (uint256 ethOut) {
        (, ethOut) = _computeSellExactIn(sender, fuIn);
    }

    function buyExactOut(address recipient, uint256 fuOut) external payable returns (uint256 ethIn) {
        uint256 fuOutPair;
        (fuOutPair, ethIn) = _computeBuyExactOut(recipient, fuOut);

        // Hitting the slippage limit will cause this transfer to revert
        payable(address(WETH)).fastSendEth(ethIn);

        WETH.fastTransfer(address(PAIR), WETH.fastBalanceOf(address(this)));
        PAIR.fastSwap(fuOutPair, 0 ether, recipient);

        // Refund excess ETH
        payable(_msgSender()).fastSendEth(address(this).balance);

        require(FU.balanceOf(recipient) != FU.whaleLimit(recipient));
    }

    function buyExactIn(address recipient, uint256 minFuOut) external payable returns (uint256 fuOut) {
        payable(address(WETH)).fastSendEth(address(this).balance);
        uint256 ethIn = WETH.fastBalanceOf(address(this));

        uint256 fuOutPair;
        (fuOutPair, fuOut) = _computeBuyExactIn(recipient, ethIn);
        if (fuOut < minFuOut) {
            revert TooMuchSlippage(FU, fuOut, minFuOut);
        }

        WETH.fastTransfer(address(PAIR), ethIn);
        PAIR.fastSwap(fuOutPair, 0 ether, recipient);

        require(FU.balanceOf(recipient) != FU.whaleLimit(recipient));
    }

    function sellExactOut(address payable recipient, uint256 ethOut, uint256 maxFuIn) external returns (uint256 fuIn) {
        address sender = _msgSender();
        (, fuIn) = _computeSellExactOut(sender, ethOut); // TODO: remove extraneous return value
        if (fuIn > maxFuIn) {
            revert TooMuchSlippage(FU, fuIn, maxFuIn);
        }

        FU.safeTransferFrom(sender, address(PAIR), fuIn);
        PAIR.fastSwap(0, ethOut, address(this));
        WETH.fastWithdraw(WETH.fastBalanceOf(address(this)));
        recipient.fastSendEth(address(this).balance);
    }

    function sellExactIn(address payable recipient, uint256 fuIn, uint256 minEthOut) external returns (uint256 ethOut) {
        // TODO: shortcut by using the balance delta of the pair
        address sender = _msgSender();
        (, ethOut) = _computeSellExactIn(sender, fuIn);
        if (ethOut < minEthOut) {
            revert TooMuchSlippage(WETH, ethOut, minEthOut);
        }

        FU.safeTransferFrom(sender, address(PAIR), fuIn);
        PAIR.fastSwap(0, ethOut, address(this));
        WETH.fastWithdraw(WETH.fastBalanceOf(address(this)));
        recipient.fastSendEth(address(this).balance);
    }

    receive() external payable {}
}
