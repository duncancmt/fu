// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TwoStepOwnable} from "./utils/TwoStepOwnable.sol";
import {Context} from "./utils/Context.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "./interfaces/IFU.sol";

import {IUniswapV2Pair, FastUniswapV2PairLib} from "./interfaces/IUniswapV2Pair.sol";
import {pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {BasisPoints, ZERO as ZERO_BP, BASIS, scaleUp} from "./types/BasisPoints.sol";
import {Settings} from "./core/Settings.sol";

import {FastTransferLib} from "./lib/FastTransferLib.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {UnsafeMath} from "./lib/UnsafeMath.sol";
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
    using UnsafeMath for uint256;
    using FastLogic for bool;
    using Ternary for bool;

    /// @custom:security non-reentrant
    IFU public immutable token;
    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;
    bool internal immutable _sortTokens;

    uint120 public lastLpBalance;
    uint120 public kTarget;
    BasisPoints public ownerFee;

    // TODO: revisit these constants
    uint256 public constant TWAP_PERIOD = 1 days;
    uint256 public constant TWAP_PERIOD_TOLERANCE = 1 hours;

    uint256 internal priceFuWethCumulativeLast;
    uint256 internal priceWethFuCumulativeLast;
    uint256 internal timestampLast;

    event OwnerFee(BasisPoints oldFee, BasisPoints newFee);
    event OracleConsultation(address indexed keeper, uint256 cumulativeFuWeth, uint256 cumulativeWethFu);
    event Buyback(address indexed caller, uint256 kTarget);

    error FeeIncreased(BasisPoints oldFee, BasisPoints newFee);
    error FeeNotZero(BasisPoints ownerFee);

    error PriceTooStale(uint256 elapsed);
    error PriceTooFresh(uint256 elapsed);
    error PriceTooLow(uint256 actualQ112, uint256 expectedQ112);

    constructor(bytes20 gitCommit, address initialOwner, BasisPoints ownerFee_, IFU token_) {
        require(_msgSender() == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        {
            bool isSimulation = block.basefee < 7 wei && block.gaslimit > 1_000_000_000 && block.number < 20_000_000;
            // slither-disable-next-line tx-origin
            require(tx.origin == 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6 || isSimulation);
        }
        require(initialOwner != address(0));
        require(ownerFee_ < BASIS);

        require(uint160(address(this)) / Settings.ADDRESS_DIVISOR == Settings.CRAZY_BALANCE_BASIS);

        emit IFU.GitCommit(gitCommit);

        _setOwner(initialOwner);
        token = token_;
        pair = pairFor(token, WETH);
        assert(token.pair() == address(pair));
        _sortTokens = address(token) > address(WETH);
        lastLpBalance = kTarget = uint120(IERC20(pair).fastBalanceOf(address(this)));
        emit Buyback(_msgSender(), kTarget);
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
            if (timestampLast + (TWAP_PERIOD + TWAP_PERIOD_TOLERANCE) > block.timestamp) {
                revert PriceTooFresh(block.timestamp - timestampLast);
            }
        }

        // this is the standard formula for taking the counterfactual cumulative of the pair at the
        // current price _without_ doing an expensive call to `pair.sync()`
        (uint256 reserveFu, uint256 reserveWeth, uint32 timestampLast_) = pair.fastGetReserves();
        (reserveFu, reserveWeth) = _sortTokens.maybeSwap(reserveFu, reserveWeth);
        unchecked {
            uint256 elapsed = uint32(block.timestamp) - timestampLast_; // masking and underflow is desired
            priceFuWethCumulativeLast =
                pair.fastPriceCumulativeLast(_sortTokens) + (reserveWeth << 112) / reserveFu * elapsed;
            priceWethFuCumulativeLast =
                pair.fastPriceCumulativeLast(!_sortTokens) + (reserveFu << 112) / reserveWeth * elapsed;
        }

        timestampLast = block.timestamp;
        emit OracleConsultation(_msgSender(), priceFuWethCumulativeLast, priceWethFuCumulativeLast);

        return true;
    }

    function _checkWethFuOraclePrice(uint256 reserveFu, uint256 reserveWeth) internal view returns (uint256 elapsed) {
        unchecked {
            elapsed = block.timestamp - timestampLast;
            if (elapsed < TWAP_PERIOD - TWAP_PERIOD_TOLERANCE) {
                revert PriceTooFresh(elapsed);
            }
            if (elapsed > TWAP_PERIOD + TWAP_PERIOD_TOLERANCE) {
                revert PriceTooStale(elapsed);
            }
            // the call to `burn` that happens before this ensures that
            // `pair.price?CumulativeLast()` is up-to-date. we don't need to handle any
            // counterfactual values.
            uint256 oraclePrice =
                uint224((pair.fastPriceCumulativeLast(!_sortTokens) - priceWethFuCumulativeLast) / elapsed);
            uint256 currentPrice = (reserveFu << 112) / reserveWeth;
            if (currentPrice < oraclePrice) {
                revert PriceTooLow(currentPrice, oraclePrice);
            }
        }
    }

    function _hypotheticalConstantProductSwap(
        uint256 amountFu,
        uint256 fuWethPriceQ112,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256) {
        unchecked {
            uint256 liquiditySquared = reserve0 * reserve1;
            uint256 reserveFu = tmp().omul(liquiditySquared, 1 << 112).div(fuWethPriceQ112).sqrt();
            uint512 n = alloc().omul(liquiditySquared, amountFu);
            uint256 d = reserveFu * (reserveFu + amountFu);
            uint256 q = n.div(d);
            return q.unsafeInc(tmp().omul(q, d) < n);
        }
    }

    function buyback() external returns (bool) {
        // adjust `kTarget` to account for any extra LP tokens that may have been sent to this
        // contract since the last time `buyback` was called
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
        // amount. the 30bp swap fee applied by the pair results in a slight underestimation of the
        // amount of LP required to burn.
        uint256 left;
        uint256 right;
        unchecked {
            left = lpBalance * liquidity;
            // slither-disable-next-line divide-before-multiply
            right = pair.fastTotalSupply() * kTarget_;
        }
        uint256 burnLp = (left - right) / liquidity; // underflow indicates that (somehow) liquidity has decreased

        // burn LP tokens and receive some of the underlying tokens
        pair.fastTransfer(address(pair), burnLp);
        (uint256 amountFu, uint256 amountWeth) = pair.fastBurn(address(this));

        // get the reserves again. we have to get them _again_ because there may be excess tokens in
        // the pair before calling `burn`. calling `burn` implicitly synchronizes the pair with its
        // balances.
        (amountFu, amountWeth) = _sortTokens.maybeSwap(amountFu, amountWeth);
        address owner_ = owner();
        BasisPoints ownerFee_ = ownerFee;
        if ((owner_ == address(0)).or(ownerFee_ == ZERO_BP)) {
            amountWeth = WETH.fastBalanceOf(address(this));
        }

        // begin to compute the amount of WETH owable to `owner()`. we must also compute the amount
        // of WETH owable to the owner as a result of converting (some of) the FU we withdrew, but
        // that will happen later.
        uint256 feeWeth = scaleUp(amountWeth, ownerFee_);
        // slither-disable-next-line unused-return
        (uint256 reserveFu, uint256 reserveWeth,) = pair.fastGetReserves();
        (reserveFu, reserveWeth) = _sortTokens.maybeSwap(reserveFu, reserveWeth);

        // consult the oracle. this is required to avoid MEV because `buyback` is permissionless
        uint256 elapsed = _checkWethFuOraclePrice(reserveFu, reserveWeth);

        // convert the fee-scaled amount of FU that we withdrew from the pair into WETH using the
        // constant-product formula. this formula does not apply the 30bp UniV2 swap fee because
        // this is only a hypothetical swap. this formula also uses the TWAP price directly, rather
        // than the current spot price. note that this calculation uses `amountFu`, which is the
        // amount *SENT BY THE PAIR*, and not the amount actually received by this contract (i.e. it
        // is the amount before FU transfer fees are taken out)
        unchecked {
            feeWeth += _hypotheticalConstantProductSwap(
                scaleUp(amountFu, ownerFee_),
                uint224((pair.fastPriceCumulativeLast(_sortTokens) - priceFuWethCumulativeLast) / elapsed),
                reserveFu,
                reserveWeth
            );
        }

        // swap the leftover WETH to FU. this is the actual buyback step
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
            (uint256 amount0, uint256 amount1) = _sortTokens.maybeSwap(swapFuOut, 0);
            pair.fastSwap(amount0, amount1, address(this));
        }

        // the last step is to pay the WETH fee to the owner and to `deliver` the balance of this
        // contract to the other tokenholders (increasing not only the price of their holdings, but
        // the actual number of tokens)
        token.fastDeliver(token.fastBalanceOf(address(this)));
        WETH.fastTransfer(owner_, WETH.fastBalanceOf(address(this)));

        // update state for next time, in case somebody sends LP tokens to this contract
        (kTarget, lastLpBalance) = (uint120(kTarget_), uint120(pair.fastBalanceOf(address(this))));
        // because we had to apply the 30bp fee when swapping WETH->FU above, the actual `k`
        // represented by the LP tokens held by this contract is _still_ above `kTarget`. attempting
        // to solve for the amount of LP tokens to burn to bring these values into exact equality
        // requires finding a root of a degree-4 polynomial, which is absolutely awful to attempt to
        // compute on-chain. so we accept this inaccuracy as a concession to the limits of
        // complexity and gas.

        emit Buyback(_msgSender(), kTarget);

        return true;
    }
}
