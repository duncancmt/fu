// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TwoStepOwnable} from "./utils/TwoStepOwnable.sol";
import {MultiCallContext} from "./utils/MultiCallContext.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "./interfaces/IFU.sol";

import {IUniswapV2Pair, FastUniswapV2PairLib} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory, FastUniswapV2FactoryLib, FACTORY} from "./interfaces/IUniswapV2Factory.sol";
import {pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {BasisPoints, ZERO as ZERO_BP, BASIS, scaleUp} from "./types/BasisPoints.sol";
import {Settings} from "./core/Settings.sol";

import {FastTransferLib} from "./lib/FastTransferLib.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {Math} from "./lib/Math.sol";
import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {Panic} from "./lib/Panic.sol";
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

/// @custom:security-contact security@fuckyou.finance
contract Buyback is TwoStepOwnable, MultiCallContext {
    using FastTransferLib for IERC20;
    using FastTransferLib for IFU;
    using FastTransferLib for IUniswapV2Pair;
    using FastFu for IFU;
    using FastUniswapV2PairLib for IUniswapV2Pair;
    using FastUniswapV2FactoryLib for IUniswapV2Factory;
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
    uint120 public liquidityTarget;
    uint16 public ownerFee;

    uint256 internal constant _TWAP_PERIOD = 1 days;
    uint256 internal constant _TWAP_PERIOD_TOLERANCE = 30 minutes;

    uint256 internal priceFuWethCumulativeLast;
    uint256 internal priceWethFuCumulativeLast;
    uint256 internal timestampLast;

    event OwnerFee(BasisPoints oldFee, BasisPoints newFee);
    event OracleConsultation(address indexed keeper, uint256 cumulativeFuWeth, uint256 cumulativeWethFu);
    event Buyback(address indexed caller, uint256 liquidityTarget);

    error FeeIncreased(BasisPoints oldFee, BasisPoints newFee);
    error FeeNotZero(BasisPoints ownerFee);

    error PriceTooStale(uint256 elapsed);
    error PriceTooFresh(uint256 elapsed);
    error PriceTooLow(uint256 actualQ112, uint256 expectedQ112);

    constructor(bytes20 gitCommit, address initialOwner, BasisPoints ownerFee_, IFU token_) {
        require(_msgSender() == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        {
            bool isSimulation =
                (block.basefee < 7 wei).and(block.gaslimit > 1_000_000_000).and(block.number < 20_000_000);
            // slither-disable-next-line tx-origin
            require((tx.origin == 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6).or(isSimulation));
        }
        require(initialOwner != address(0));
        require(ownerFee_ < BASIS);

        require(uint160(address(this)) >> Settings.ADDRESS_SHIFT == Settings.CRAZY_BALANCE_BASIS);

        emit IFU.GitCommit(gitCommit);

        _setOwner(initialOwner);
        token = token_;
        pair = pairFor(token, WETH);
        assert(token.pair() == address(pair));
        _sortTokens = address(token) > address(WETH);
        lastLpBalance = liquidityTarget = uint120(IERC20(pair).fastBalanceOf(address(this)));
        emit Buyback(_msgSender(), liquidityTarget);
        ownerFee = uint16(BasisPoints.unwrap(ownerFee_));
        emit OwnerFee(BASIS, ownerFee_);

        _consult();
    }

    function setFee(BasisPoints newOwnerFee) external onlyOwner returns (bool) {
        BasisPoints oldFee = BasisPoints.wrap(ownerFee);
        if (newOwnerFee > oldFee) {
            revert FeeIncreased(oldFee, newOwnerFee);
        }
        ownerFee = uint16(BasisPoints.unwrap(newOwnerFee));
        emit OwnerFee(oldFee, newOwnerFee);
        return true;
    }

    function renounceOwnership() public override returns (bool) {
        if (BasisPoints.wrap(ownerFee) != ZERO_BP) {
            revert FeeNotZero(BasisPoints.wrap(ownerFee));
        }
        return super.renounceOwnership();
    }

    function _consult() private {
        // this is the standard formula for taking the counterfactual cumulative of the pair at the
        // current price _without_ doing an expensive call to `pair.sync()`
        (uint256 reserveFu, uint256 reserveWeth, uint32 timestampLast_) = pair.fastGetReserves();
        (reserveFu, reserveWeth) = _sortTokens.maybeSwap(reserveFu, reserveWeth);
        unchecked {
            // slither-disable-next-line timestamp
            uint256 elapsed = uint32(block.timestamp) - timestampLast_; // masking and underflow is desired
            // `_sortTokens == false` means that WETH is token1 and FU is token0
            // `_sortTokens == true`  means that WETH is token0 and FU is token1
            // slither-disable-next-line divide-before-multiply
            priceFuWethCumulativeLast =
                pair.fastPriceCumulativeLast(_sortTokens) + (reserveWeth << 112).unsafeDiv(reserveFu) * elapsed;
            // slither-disable-next-line divide-before-multiply
            priceWethFuCumulativeLast =
                pair.fastPriceCumulativeLast(!_sortTokens) + (reserveFu << 112).unsafeDiv(reserveWeth) * elapsed;
        }

        timestampLast = block.timestamp;
        emit OracleConsultation(_msgSender(), priceFuWethCumulativeLast, priceWethFuCumulativeLast);
    }

    function consult() public returns (bool) {
        unchecked {
            // slither-disable-next-line timestamp
            if (timestampLast + (_TWAP_PERIOD + _TWAP_PERIOD_TOLERANCE) > block.timestamp) {
                revert PriceTooFresh(block.timestamp - timestampLast);
            }
        }

        _consult();

        return true;
    }

    function _checkWethFuOraclePrice(uint256 reserveFu, uint256 reserveWeth)
        internal
        view
        returns (uint256 elapsed, uint256 priceWethFuCumulative)
    {
        unchecked {
            elapsed = block.timestamp - timestampLast;
            if (elapsed < _TWAP_PERIOD - _TWAP_PERIOD_TOLERANCE) {
                revert PriceTooFresh(elapsed);
            }
            if (elapsed > _TWAP_PERIOD + _TWAP_PERIOD_TOLERANCE) {
                revert PriceTooStale(elapsed);
            }
            // the call to `burn` that happens before this ensures that
            // `pair.price?CumulativeLast()` is up-to-date. we don't need to handle any
            // counterfactual values.
            priceWethFuCumulative = pair.fastPriceCumulativeLast(!_sortTokens);
            uint256 wethFuPriceQ112 = uint224((priceWethFuCumulative - priceWethFuCumulativeLast).unsafeDiv(elapsed));
            // `wethFuPriceQ112` is a slight overestimate of the mean FU/WETH ratio, under the
            // assumption that the price is a geometric process. this makes this check slightly
            // stricter than the corresponding geometric mean oracle check.
            uint256 currentPriceQ112 = (reserveFu << 112).unsafeDiv(reserveWeth);
            if (currentPriceQ112 < wethFuPriceQ112) {
                revert PriceTooLow(currentPriceQ112, wethFuPriceQ112);
            }
        }
    }

    function _hypotheticalConstantProductSwap(uint256 amountFu, uint256 elapsed, uint256 reserve0, uint256 reserve1)
        internal
        view
        returns (uint256 amountWeth, uint256 priceFuWethCumulative)
    {
        unchecked {
            uint256 liquiditySquared = reserve0 * reserve1;
            priceFuWethCumulative = pair.fastPriceCumulativeLast(_sortTokens);
            // `fuWethPriceQ112` is a slight overestimate of the WETH/FU ratio, under the assumption
            // that the price is a geometric Brownian walk.
            uint256 fuWethPriceQ112 = uint224((priceFuWethCumulative - priceFuWethCumulativeLast).unsafeDiv(elapsed));
            // consequently, `reserveFu` is an underestimate of the average reserve of FU; FU is
            // overvalued relative to WETH.
            uint256 reserveFu = tmp().omul(liquiditySquared, 1 << 112).div(fuWethPriceQ112).sqrt();
            // so when we perform the constant-product swap FU->WETH, we get more WETH. in other
            // words, we err on the side of giving `owner()` a too-favorable price during this
            // hypothetical swap.
            amountWeth = tmp().omul(liquiditySquared, amountFu).div(reserveFu * (reserveFu + amountFu));
        }
    }

    function buyback() external returns (bool) {
        // adjust `liquidityTarget` to account for any extra LP tokens that may have been sent to
        // this contract since the last time `buyback` was called
        uint256 lpBalance = pair.fastBalanceOf(address(this));
        uint256 liquidityTarget_;
        unchecked {
            liquidityTarget_ = (liquidityTarget * lpBalance).unsafeDivUp(lastLpBalance);
        }

        // compute the underlying liquidity
        uint256 liquidity;
        unchecked {
            // slither-disable-next-line unused-return
            (uint256 reserve0, uint256 reserve1,) = pair.fastGetReserves();
            liquidity = (reserve0 * reserve1).sqrt();
        }

        // compute the amount of LP to be burned to (approximately) bring `liquidity` back to the
        // target amount. the 30bp swap fee applied by the pair results in a slight underestimation
        // of the amount of LP required to burn. we compute:
        //     (lpBalance * totalLiquidity - totalLpSupply * targetLiquidity) / totalLiquidity
        uint256 left;
        unchecked {
            left = lpBalance * liquidity;
        }
        // if Uniswap turns on the fee switch, we need to adjust `totalLpSupply` before we call burn
        uint256 totalLpSupply = pair.fastTotalSupply();
        if (FACTORY.fastFeeTo() != address(0)) {
            uint256 kLast = pair.fastKLast();
            if (kLast != 0) {
                uint256 liquidityLast = kLast.sqrt();
                uint256 liquidityGrowth = liquidity - liquidityLast; // underflow indicates that (somehow) liquidity has decreased
                unchecked {
                    totalLpSupply += totalLpSupply * liquidityGrowth / (liquidity * 5 + liquidityLast);
                }
            }
        }
        uint256 right;
        unchecked {
            // slither-disable-next-line divide-before-multiply
            right = totalLpSupply * liquidityTarget_;
        }
        uint256 burnLp = (left - right).unsafeDiv(liquidity); // underflow indicates that (somehow) liquidity has decreased

        // burn LP tokens and receive some of the underlying tokens
        pair.fastTransfer(address(pair), burnLp);
        (uint256 amountFu, uint256 amountWeth) = pair.fastBurn(address(this));

        // get the reserves again. we have to get them _again_ because there may be excess tokens in
        // the pair before calling `burn`. calling `burn` implicitly synchronizes the pair with its
        // balances.
        // `_sortTokens == false` means that WETH is token1 and FU is token0
        // `_sortTokens == true`  means that WETH is token0 and FU is token1
        (amountFu, amountWeth) = _sortTokens.maybeSwap(amountFu, amountWeth);
        address owner_ = owner();
        BasisPoints ownerFee_ = BasisPoints.wrap(ownerFee);
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
        (uint256 elapsed, uint256 priceWethFuCumulative) = _checkWethFuOraclePrice(reserveFu, reserveWeth);

        // convert the fee-scaled amount of FU that we withdrew from the pair into WETH using the
        // constant-product formula. this formula does not apply the 30bp UniV2 swap fee because
        // this is only a hypothetical swap. this formula also uses the TWAP price directly, rather
        // than the current spot price. note that this calculation uses `amountFu`, which is the
        // amount *SENT BY THE PAIR*, and not the amount actually received by this contract (i.e. it
        // is the amount before FU transfer fees are taken out)
        uint256 priceFuWethCumulative;
        unchecked {
            uint256 amountWethFromFu;
            (amountWethFromFu, priceFuWethCumulative) =
                _hypotheticalConstantProductSwap(scaleUp(amountFu, ownerFee_), elapsed, reserveFu, reserveWeth);
            feeWeth += amountWethFromFu;
        }

        // swap the leftover WETH to FU. this is the actual buyback step
        uint256 swapWethIn = amountWeth - feeWeth; // underflow indicates price too low relative to `ownerFee`
        uint256 swapFuOut;
        unchecked {
            uint256 swapWethWithFee = BasisPoints.unwrap(BASIS - UNIV2_FEE) * swapWethIn;
            uint256 n = swapWethWithFee * reserveFu;
            uint256 d = BasisPoints.unwrap(BASIS) * reserveWeth + swapWethWithFee;
            swapFuOut = n.unsafeDiv(d);
        }
        WETH.fastTransfer(address(pair), swapWethIn);
        {
            (uint256 amount0, uint256 amount1) = _sortTokens.maybeSwap(swapFuOut, 0);
            pair.fastSwap(amount0, amount1, address(this));
        }

        // the last step is to pay the WETH fee to the owner and to `deliver` the balance of this
        // contract to the other tokenholders (increasing not only the price of their holdings, but
        // also the actual number of tokens)
        token.fastDeliver(token.fastBalanceOf(address(this)));
        WETH.fastTransfer(owner_, WETH.fastBalanceOf(address(this)));

        // update state for next time, in case somebody sends LP tokens to this contract
        (liquidityTarget, lastLpBalance) = (uint120(liquidityTarget_), uint120(pair.fastBalanceOf(address(this))));
        // because we had to apply the 30bp fee when swapping WETH->FU above, the actual `liquidity`
        // represented by the LP tokens held by this contract is _still_ above
        // `liquidityTarget`. attempting to solve for the amount of LP tokens to burn to bring these
        // values into exact equality requires finding a root of a degree-4 polynomial, which is
        // absolutely awful to attempt to compute on-chain. so we accept this inaccuracy as a
        // concession to the limits of complexity and gas.
        (priceFuWethCumulativeLast, priceWethFuCumulativeLast, timestampLast) =
            (priceFuWethCumulative, priceWethFuCumulative, block.timestamp);

        emit Buyback(_msgSender(), liquidityTarget);

        return true;
    }
}
