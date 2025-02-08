// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Base} from "./core/ERC20Base.sol";
import {Context} from "./utils/Context.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";
import {TransientStorageLayout} from "./core/TransientStorageLayout.sol";
import {Checkpoints, LibCheckpoints} from "./core/Checkpoints.sol";
import {RebaseQueue, LibRebaseQueue} from "./core/RebaseQueue.sol";
import {MoonPhase} from "./core/MoonPhase.sol";

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares, ZERO as ZERO_SHARES, ONE as ONE_SHARE, SharesStorage} from "./types/Shares.sol";
import {Tokens} from "./types/Tokens.sol";
import {SharesToTokens} from "./types/TokensXShares.sol";
import {SharesToTokensProportional} from "./types/TokensXBasisPointsXShares.sol";
import {Votes, toVotes} from "./types/Votes.sol";
import {scale, cast, castUp} from "./types/TokensXBasisPoints.sol";
import {SharesXBasisPoints, scale} from "./types/SharesXBasisPoints.sol";
import {
    CrazyBalance,
    toCrazyBalance,
    ZERO as ZERO_BALANCE,
    MAX as MAX_BALANCE,
    CrazyBalanceArithmetic
} from "./types/CrazyBalance.sol";

import {ChecksumAddress} from "./lib/ChecksumAddress.sol";
import {IPFS} from "./lib/IPFS.sol";
import {FastTransferLib} from "./lib/FastTransferLib.sol";
import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {FastLogic} from "./lib/FastLogic.sol";

/// @custom:security non-reentrant
IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

library UnsafeArray {
    function unsafeGet(address[] memory a, uint256 i) internal pure returns (address r) {
        assembly ("memory-safe") {
            r := mload(add(a, add(0x20, shl(0x05, i))))
        }
    }
}

/// @custom:security-contact security@fuckyou.finance
contract FU is ERC20Base, TransientStorageLayout, Context {
    using ChecksumAddress for address;
    using {toCrazyBalance} for uint256;
    using SharesToTokens for Shares;
    using SharesToTokensProportional for SharesXBasisPoints;
    using CrazyBalanceArithmetic for Shares;
    using CrazyBalanceArithmetic for Tokens;
    using {toVotes} for Shares;
    using LibCheckpoints for Checkpoints;
    using LibRebaseQueue for RebaseQueue;
    using IPFS for string;
    using IPFS for bytes32;
    using FastTransferLib for address payable;
    using FastTransferLib for IERC20;
    using UnsafeArray for address[];
    using UnsafeMath for uint256;
    using FastLogic for bool;

    function totalSupply() external view override returns (uint256) {
        Storage storage $ = _$();
        return ($.totalSupply + $.pairTokens).toExternal();
    }

    /// @custom:security non-reentrant
    address public immutable override pair;

    bytes32 private immutable _imageHash;

    function image() external view override returns (string memory) {
        return _imageHash.CIDv0();
    }

    constructor(bytes20 gitCommit, string memory image_, address[] memory initialHolders) payable {
        assert(Settings.SHARES_TO_VOTES_DIVISOR >= Settings.INITIAL_SHARES_RATIO);
        assert(
            Shares.unwrap(Settings.oneTokenInShares())
                > Settings.MIN_SHARES_RATIO * Tokens.unwrap(Settings.INITIAL_SUPPLY)
        );

        require(_msgSender() == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        {
            bool isSimulation = block.basefee < 7 wei && block.gaslimit > 1_000_000_000 && block.number < 20_000_000;
            // slither-disable-next-line tx-origin
            require(tx.origin == 0x3D87e294ba9e29d2B5a557a45afCb0D052a13ea6 || isSimulation);
        }
        require(address(this).balance >= 5 ether);
        uint256 length = initialHolders.length;
        require(length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = address(pairFor(WETH, this));
        require(uint160(pair) / Settings.ADDRESS_DIVISOR == 1);

        assembly ("memory-safe") {
            log0(add(0x20, image_), mload(image_))
        }
        emit GitCommit(gitCommit);
        _imageHash = image_.dagPbUnixFsHash();

        payable(address(WETH)).fastSendEth(address(this).balance);
        WETH.fastTransfer(pair, WETH.fastBalanceOf(address(this)));

        Storage storage $ = _$();

        Tokens pairTokens = Settings.INITIAL_SUPPLY.div(Settings.INITIAL_LIQUIDITY_DIVISOR);
        pairTokens = pairTokens - Tokens.wrap(Tokens.unwrap(pairTokens) % Settings.CRAZY_BALANCE_BASIS);
        $.pairTokens = pairTokens;
        emit Transfer(address(0), pair, pairTokens.toExternal());

        Tokens totalSupply_ = Settings.INITIAL_SUPPLY - pairTokens;
        $.totalSupply = totalSupply_;
        Shares totalShares = Shares.wrap(Tokens.unwrap(totalSupply_) * Settings.INITIAL_SHARES_RATIO);
        $.totalShares = totalShares;

        {
            // The queue is empty, so we have to special-case the first insertion. `DEAD` will
            // always hold a token balance, which makes many things simpler.
            $.sharesOf[DEAD] = Settings.oneTokenInShares().store();
            Tokens tokens = $.sharesOf[DEAD].load().toTokens(totalSupply_, totalShares);
            emit Transfer(address(0), DEAD, tokens.toExternal());
            $.rebaseQueue.initialize(DEAD, tokens);
        }
        {
            Shares toMint = totalShares - $.sharesOf[DEAD].load();
            address prev = initialHolders.unsafeGet(0);
            require(uint160(prev) >= Settings.ADDRESS_DIVISOR);
            // slither-disable-next-line divide-before-multiply
            Shares sharesRest = toMint.div(length);
            {
                Shares sharesFirst = toMint - sharesRest.mul(length - 1);
                Tokens amount = sharesFirst.toTokens(totalSupply_, totalShares);

                require(prev != DEAD);
                $.sharesOf[prev] = sharesFirst.store();
                emit Transfer(address(0), prev, amount.toExternal());
                $.rebaseQueue.enqueue(prev, amount);
            }
            {
                Tokens amount = sharesRest.toTokens(totalSupply_, totalShares);
                SharesStorage sharesRestStorage = sharesRest.store();
                for (uint256 i = 1; i < length; i = i.unsafeInc()) {
                    address to = initialHolders.unsafeGet(i);
                    require(to != DEAD);
                    require(to > prev);
                    $.sharesOf[to] = sharesRestStorage;
                    emit Transfer(address(0), to, amount.toExternal());
                    $.rebaseQueue.enqueue(to, amount);
                    prev = to;
                }
            }
        }

        try FACTORY.createPair(WETH, this) returns (IUniswapV2Pair newPair) {
            require(pair == address(newPair));
        } catch {
            require(pair == address(FACTORY.getPair(WETH, this)));
        }

        // We can't call `pair.mint` from within the constructor because it wants to call back into
        // us with `balanceOf`. The call to `mint` and the check that liquidity isn't being stolen
        // is performed in the deployment script. Its atomicity is enforced by the check against
        // `tx.origin` above.
    }

    function _consumeNonce(Storage storage $, address account) internal override returns (uint256) {
        unchecked {
            return $.nonces[account]++;
        }
    }

    function _check() private view returns (bool r) {
        assembly ("memory-safe") {
            mstore(0x20, coinbase())
            mstore(0x0c, gasprice())
            mstore(0x00, prevrandao())
            r := shr(0xff, keccak256(0x00, 0x40))
        }
    }

    function _success() internal view override returns (bool) {
        if (_check()) {
            assembly ("memory-safe") {
                stop()
            }
        }
        return true;
    }

    function _whaleLimit(Shares shares, Shares totalShares_)
        private
        pure
        returns (Shares limit, Shares newTotalShares)
    {
        Shares uninvolved = totalShares_ - shares;
        limit = uninvolved.div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE) - ONE_SHARE;
        newTotalShares = uninvolved + limit;
    }

    function _applyWhaleLimit(Shares shares, Shares totalShares_) private pure returns (Shares, Shares) {
        (Shares limit, Shares newTotalShares) = _whaleLimit(shares, totalShares_);
        if (shares > limit) {
            totalShares_ = newTotalShares;
            shares = limit;
        }
        return (shares, totalShares_);
    }

    function _applyWhaleLimit(Shares shares0, Shares shares1, Shares totalShares_)
        private
        pure
        returns (Shares, Shares, Shares)
    {
        (Shares sharesHi, Shares sharesLo) = (shares0 > shares1) ? (shares0, shares1) : (shares1, shares0);
        (Shares firstLimit, Shares newTotalShares) = _whaleLimit(sharesHi, totalShares_);
        if (sharesHi > firstLimit) {
            Shares uninvolved = totalShares_ - sharesHi - sharesLo;
            Shares secondLimit = uninvolved.div(Settings.ANTI_WHALE_DIVISOR_MINUS_TWO) - ONE_SHARE;
            if (sharesLo > secondLimit) {
                totalShares_ = uninvolved + secondLimit.mul(2);
                sharesHi = secondLimit;
                sharesLo = secondLimit;
                // TODO: verify that this *EXACTLY* satisfied the postcondition `sharesHi == sharesLo == totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE`
            } else {
                totalShares_ = newTotalShares;
                sharesHi = firstLimit;
            }
        }
        (shares0, shares1) = (shares0 > shares1) ? (sharesHi, sharesLo) : (sharesLo, sharesHi);
        return (shares0, shares1, totalShares_);
    }

    function _loadAccount(Storage storage $, address account)
        private
        view
        returns (Shares originalShares, Shares cachedShares, Shares cachedTotalShares)
    {
        originalShares = $.sharesOf[account].load();
        (cachedShares, cachedTotalShares) = _applyWhaleLimit(originalShares, $.totalShares);
    }

    function _loadAccounts(Storage storage $, address account0, address account1)
        private
        view
        returns (
            Shares originalShares0,
            Shares cachedShares0,
            Shares originalShares1,
            Shares cachedShares1,
            Shares cachedTotalShares
        )
    {
        originalShares0 = $.sharesOf[account0].load();
        originalShares1 = $.sharesOf[account1].load();
        (cachedShares0, cachedShares1, cachedTotalShares) =
            _applyWhaleLimit(originalShares0, originalShares1, $.totalShares);
    }

    function _balanceOf(Storage storage $, address account)
        private
        view
        returns (
            CrazyBalance balance,
            Shares originalShares,
            Shares cachedShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        )
    {
        (originalShares, cachedShares, cachedTotalShares) = _loadAccount($, account);
        cachedTotalSupply = $.totalSupply;
        balance = cachedShares.toCrazyBalance(account, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        Storage storage $ = _$();
        if (account == pair) {
            return $.pairTokens.toPairBalance().toExternal();
        }
        if (account == DEAD) {
            return $.sharesOf[DEAD].load().toCrazyBalance(DEAD, $.totalSupply, $.totalShares).toExternal();
        }
        (CrazyBalance balance,,,,) = _balanceOf($, account);
        return balance.toExternal();
    }

    function _balanceOf(Storage storage $, address account0, address account1)
        private
        view
        returns (
            CrazyBalance balance0,
            Shares originalShares0,
            Shares cachedShares0,
            Shares originalShares1,
            Shares cachedShares1,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        )
    {
        (originalShares0, cachedShares0, originalShares1, cachedShares1, cachedTotalShares) =
            _loadAccounts($, account0, account1);
        cachedTotalSupply = $.totalSupply;
        balance0 = cachedShares0.toCrazyBalance(account0, cachedTotalSupply, cachedTotalShares);
    }

    function _tax() private view returns (BasisPoints) {
        return MoonPhase.moonPhase(block.timestamp);
    }

    function tax() external view override returns (uint256) {
        return BasisPoints.unwrap(_tax());
    }

    function whaleLimit(address potentialWhale) external view override returns (uint256) {
        if ((potentialWhale == pair).or(potentialWhale == DEAD)) {
            return type(uint256).max;
        }
        // This looks gas-wasteful and baroque, but loading all this additional state is required for
        // exact correctness in the face of rounding error. This exactly replicates the rounding
        // behavior applied when calling `balanceOf(potentialWhale)`.
        Storage storage $ = _$();
        (Shares limit, Shares totalShares_) = _whaleLimit($.sharesOf[potentialWhale].load(), $.totalShares);
        return limit.toCrazyBalance(potentialWhale, $.totalSupply, totalShares_).toExternal();
    }

    function _pokeRebaseQueueFrom(
        Storage storage $,
        address from,
        CrazyBalance balance,
        CrazyBalance amount,
        Shares originalShares,
        Shares newShares,
        Tokens newTotalSupply,
        Shares newTotalShares
    ) private {
        if (amount == balance) {
            if (originalShares != ZERO_SHARES) {
                $.rebaseQueue.dequeue(from);
            }
        } else {
            $.rebaseQueue.moveToBack(from, newShares, newTotalSupply, newTotalShares);
        }
    }

    function _pokeRebaseQueueTo(
        Storage storage $,
        address to,
        CrazyBalance amount,
        Shares originalShares,
        Shares newShares,
        Tokens newTotalSupply,
        Shares newTotalShares
    ) private {
        if (originalShares == ZERO_SHARES) {
            if (amount != ZERO_BALANCE) {
                $.rebaseQueue.enqueue(to, newShares, newTotalSupply, newTotalShares);
            }
        } else {
            $.rebaseQueue.moveToBack(to, newShares, newTotalSupply, newTotalShares);
        }
    }

    function _transferFromPair(Storage storage $, address pair_, address to, CrazyBalance amount)
        private
        returns (bool)
    {
        // We don't need to check that `pair` is transferring less than its balance. The
        // `UniswapV2Pair` code does that for us. Additionally, `pair`'s balance can never reach
        // zero.

        (Shares originalShares, Shares cachedShares, Shares cachedTotalShares) = _loadAccount($, to);
        Tokens cachedTotalSupply = $.totalSupply;
        Tokens amountTokens = amount.toPairTokens();

        BasisPoints taxRate = _tax();
        Shares newShares;
        Shares newTotalShares;
        Tokens newTotalSupply;
        // TODO: I haven't thoroughly thought through the rounding behavior of this check. there may
        // be an off-by-one. but also maybe it doesn't matter because `getTransferSharesFromPair`
        // *mostly* works correctly when values aren't *too* extreme
        Tokens balanceTokensHi = cachedShares.toTokensUp(cachedTotalSupply, cachedTotalShares);
        if (
            castUp(scale(amountTokens, BASIS - taxRate)) + balanceTokensHi
                >= (cachedTotalSupply - balanceTokensHi).div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE)
        ) {
            newShares = (cachedTotalShares - cachedShares).div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE) - ONE_SHARE;
            newTotalShares = cachedTotalShares + newShares - cachedShares;
            newTotalSupply = cachedTotalSupply + amountTokens;
        } else {
            (newShares, newTotalShares, newTotalSupply) = ReflectMath.getTransferSharesFromPair(
                taxRate, cachedTotalSupply, cachedTotalShares, amountTokens, cachedShares
            );
            // TODO: this is inelegant. can this be moved into the `if` statement immediately above?
            (newShares, newTotalShares) = _applyWhaleLimit(newShares, newTotalShares);
        }

        // Take note of the mismatch between the holder/recipient of the tokens/shares (`to`) and
        // the account for whom we calculate the balance delta (`pair`). The `amount` field of the
        // `Transfer` event is relative to the sender of the tokens.
        CrazyBalance transferAmount = newShares.toPairBalance(newTotalSupply, newTotalShares)
            - cachedTotalShares.toPairBalance(cachedTotalSupply, cachedTotalShares);
        CrazyBalance burnAmount = amount - transferAmount;

        // State modification starts here. No more bailing out allowed.
        $.rebaseQueue.rebaseFor(to, cachedShares, cachedTotalSupply, cachedTotalShares);

        $.pairTokens = $.pairTokens - amountTokens;
        $.sharesOf[to] = newShares.store();
        $.totalSupply = newTotalSupply;
        $.totalShares = newTotalShares;

        emit Transfer(pair_, to, transferAmount.toExternal());
        emit Transfer(pair_, address(0), burnAmount.toExternal());

        if (newShares >= originalShares) {
            $.checkpoints.mint($.delegates[to], newShares.toVotes() - originalShares.toVotes(), clock());
        } else {
            $.checkpoints.burn($.delegates[to], originalShares.toVotes() - newShares.toVotes(), clock());
        }

        _pokeRebaseQueueTo($, to, amount, originalShares, newShares, newTotalSupply, newTotalShares);

        $.rebaseQueue.processQueue($.sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }

    function _transferToPair(Storage storage $, address from, address pair_, CrazyBalance amount)
        private
        returns (bool)
    {
        (
            CrazyBalance balance,
            Shares originalShares,
            Shares cachedShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf($, from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Tokens cachedPairTokens = $.pairTokens;
        BasisPoints taxRate = _tax();
        Shares newShares;
        Shares newTotalShares;
        Tokens transferTokens;
        Tokens newTotalSupply;
        if (amount == balance) {
            transferTokens = scale(cachedShares, BASIS - taxRate).toTokens(cachedTotalSupply, cachedTotalShares);
            newTotalSupply = cachedTotalSupply - transferTokens;
            newShares = ZERO_SHARES;
            newTotalShares = cachedTotalShares - cachedShares;
        } else {
            (newShares, newTotalShares, transferTokens, newTotalSupply) = ReflectMath.getTransferSharesToPair(
                taxRate, cachedTotalSupply, cachedTotalShares, amount.toTokens(from), cachedShares
            );
        }
        Tokens newPairTokens = cachedPairTokens + transferTokens;

        // Take note of the mismatch between who is holding the tokens (`pair`) and the address for
        // whom the `CrazyBalance` is being calculated (`from`). We're converting `pair`'s balance
        // delta into units as if it were held by `from`.
        CrazyBalance transferAmount = newPairTokens.toCrazyBalance(from) - cachedPairTokens.toCrazyBalance(from);
        CrazyBalance burnAmount = amount - transferAmount;

        // There is no need to apply the whale limit. `pair` holds tokens directly (not shares) and
        // is allowed to go over the limit.

        // State modification starts here. No more bailing out allowed.
        $.rebaseQueue.rebaseFor(from, cachedShares, cachedTotalSupply, cachedTotalShares);

        $.sharesOf[from] = newShares.store();
        $.pairTokens = newPairTokens;
        $.totalSupply = newTotalSupply;
        $.totalShares = newTotalShares;

        emit Transfer(from, pair_, transferAmount.toExternal());
        emit Transfer(from, address(0), burnAmount.toExternal());

        $.checkpoints.burn($.delegates[from], originalShares.toVotes() - newShares.toVotes(), clock());

        _pokeRebaseQueueFrom($, from, balance, amount, originalShares, newShares, cachedTotalSupply, newTotalShares);

        $.rebaseQueue.processQueue($.sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }

    function _transfer(Storage storage $, address from, address to, CrazyBalance amount)
        internal
        override
        returns (bool)
    {
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }

        address pair_ = pair;
        if (to == pair_) {
            if (from == to) {
                if (_check()) {
                    revert ERC20InvalidReceiver(to);
                }
                return false;
            }
            return _transferToPair($, from, to, amount);
        }

        if ((to == DEAD).or(to == address(this)).or(uint160(to) / Settings.ADDRESS_DIVISOR == 0)) {
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }

        if (from == pair_) {
            return _transferFromPair($, from, to, amount);
        }

        if (from == to) {
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }

        (
            CrazyBalance fromBalance,
            Shares originalFromShares,
            Shares cachedFromShares,
            Shares originalToShares,
            Shares cachedToShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf($, from, to);

        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        BasisPoints taxRate = _tax();
        Shares newFromShares;
        Shares newToShares;
        Shares newTotalShares;
        if (amount == fromBalance) {
            (newToShares, newTotalShares) = ReflectMath.getTransferShares(
                taxRate, cachedTotalShares, cachedFromShares, cachedToShares
            );
            newFromShares = ZERO_SHARES;
        } else {
            // TODO: reorganize these `if` statements so that we can avoid duplicating this computation
            (newFromShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                amount.toTokens(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
        }

        if (newToShares >= (newTotalShares - newToShares).div(Settings.ANTI_WHALE_DIVISOR_MINUS_ONE)) {
            if (amount == fromBalance) {
                (cachedToShares, newToShares, newTotalShares) =
                    ReflectMath.getTransferSharesToWhale(taxRate, cachedTotalShares, cachedFromShares, cachedToShares);
                newFromShares = ZERO_SHARES;
            } else {
                // TODO: see above TODO
                (newFromShares, cachedToShares, newToShares, newTotalShares) = ReflectMath.getTransferSharesToWhale(
                    amount.toTokens(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
                );
            }
            // The quantity `cachedToShares` is counterfactual. We violate (temporarily) the
            // requirement that the sum of all accounts' shares equal the total shares.
        }

        // Take note of the `to`/`from` mismatch here. We're converting `to`'s balance into
        // units as if it were held by `from`. Also note that when `to` is a whale, the `amount`
        // emitted in the event does not accurately reflect the change in balance.
        CrazyBalance transferAmount = newToShares.toCrazyBalance(from, cachedTotalSupply, newTotalShares)
            - cachedToShares.toCrazyBalance(from, cachedTotalSupply, cachedTotalShares);
        CrazyBalance burnAmount = amount - transferAmount;

        // State modification starts here. No more bailing out allowed.
        $.rebaseQueue.rebaseFor(from, cachedFromShares, cachedTotalSupply, cachedTotalShares);
        $.rebaseQueue.rebaseFor(to, cachedToShares, cachedTotalSupply, cachedTotalShares);

        // The computation in `ReflectMath.getTransferShares` (whichever version we used) enforces
        // the postcondition that `from` and `to` come in under the whale limit. So we don't need to
        // check, we can just write the values to storage.
        $.sharesOf[from] = newFromShares.store();
        $.sharesOf[to] = newToShares.store();
        $.totalShares = newTotalShares;
        emit Transfer(from, to, transferAmount.toExternal());
        emit Transfer(from, address(0), burnAmount.toExternal());

        if (newToShares >= originalToShares) {
            $.checkpoints.transfer(
                $.delegates[from],
                $.delegates[to],
                newToShares.toVotes() - originalToShares.toVotes(),
                originalFromShares.toVotes() - newFromShares.toVotes(),
                clock()
            );
        } else {
            $.checkpoints.burn(
                $.delegates[from],
                originalFromShares.toVotes() - newFromShares.toVotes(),
                $.delegates[to],
                originalToShares.toVotes() - newToShares.toVotes(),
                clock()
            );
        }

        _pokeRebaseQueueFrom(
            $, from, fromBalance, amount, originalFromShares, newFromShares, cachedTotalSupply, newTotalShares
        );
        _pokeRebaseQueueTo($, to, amount, originalToShares, newToShares, cachedTotalSupply, newTotalShares);

        $.rebaseQueue.processQueue($.sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }

    function _approve(Storage storage $, address owner, address spender, CrazyBalance amount)
        internal
        override
        returns (bool)
    {
        if (spender == PERMIT2) {
            return true;
        }
        $.allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount.toExternal());
        return true;
    }

    function temporaryApprove(address spender, uint256 amount) external override returns (bool) {
        if (spender == PERMIT2) {
            return _success();
        }
        _setTemporaryAllowance(_msgSender(), spender, amount.toCrazyBalance());
        return _success();
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        if (owner == pair) {
            return 0;
        }
        if (spender == PERMIT2) {
            return type(uint256).max;
        }
        CrazyBalance temporaryAllowance = _getTemporaryAllowance(owner, spender);
        if (temporaryAllowance.isMax()) {
            return temporaryAllowance.toExternal();
        }
        return _$().allowance[owner][spender].saturatingAdd(temporaryAllowance).toExternal();
    }

    function _checkAllowance(Storage storage $, address owner, CrazyBalance amount)
        internal
        view
        override
        returns (bool, CrazyBalance, CrazyBalance)
    {
        if (owner == pair) {
            if (amount == ZERO_BALANCE) {
                return (true, ZERO_BALANCE, ZERO_BALANCE);
            }
            if (_check()) {
                revert ERC20InsufficientAllowance(_msgSender(), 0, amount.toExternal());
            }
            return (false, ZERO_BALANCE, ZERO_BALANCE);
        }
        if (_msgSender() == PERMIT2) {
            return (true, MAX_BALANCE, ZERO_BALANCE);
        }
        CrazyBalance currentTempAllowance = _getTemporaryAllowance(owner, _msgSender());
        if (currentTempAllowance >= amount) {
            return (true, currentTempAllowance, ZERO_BALANCE);
        }
        CrazyBalance currentAllowance = $.allowance[owner][_msgSender()];
        if (currentAllowance >= amount - currentTempAllowance) {
            return (true, currentTempAllowance, currentAllowance);
        }
        if (_check()) {
            revert ERC20InsufficientAllowance(_msgSender(), currentAllowance.toExternal(), amount.toExternal());
        }
        return (false, ZERO_BALANCE, ZERO_BALANCE);
    }

    function _spendAllowance(
        Storage storage $,
        address owner,
        CrazyBalance amount,
        CrazyBalance currentTempAllowance,
        CrazyBalance currentAllowance
    ) internal override returns (bool) {
        if (currentAllowance == ZERO_BALANCE) {
            _setTemporaryAllowance(owner, _msgSender(), currentTempAllowance - amount);
            return true;
        }
        if (currentTempAllowance != ZERO_BALANCE) {
            amount = amount - currentTempAllowance;
            _setTemporaryAllowance(owner, _msgSender(), ZERO_BALANCE);
        }
        if (currentAllowance.isMax()) {
            return true;
        }
        return _approve($, owner, _msgSender(), currentAllowance - amount);
    }

    function symbol() external view override returns (string memory r) {
        // slither-disable-next-line tx-origin
        if (tx.origin == address(0)) {
            return "FU";
        }
        assembly ("memory-safe") {
            r := mload(0x40)
            mstore(0x40, add(0x0a, r))
        }
        // slither-disable-next-line unused-return
        _msgSender().toChecksumAddress();
        assembly ("memory-safe") {
            mstore(add(0x0a, r), 0x4675636b20796f752c20)
            mstore(r, 0x35)
            mstore8(add(0x54, r), 0x21)
            mstore(0x40, add(0x60, r))
        }
    }

    uint8 public constant override decimals = Settings.DECIMALS;

    function clock() public view override returns (uint48) {
        unchecked {
            // slither-disable-next-line divide-before-multiply
            return uint48(block.timestamp / 1 days * 1 days);
        }
    }

    // slither-disable-next-line naming-convention
    string public constant override CLOCK_MODE = "mode=timestamp&epoch=1970-01-01T00%3A00%3A00Z&quantum=86400";

    function getVotes(address account) external view override returns (uint256) {
        return _$().checkpoints.current(account).toExternal();
    }

    function getPastVotes(address account, uint256 timepoint) external view override returns (uint256) {
        return _$().checkpoints.get(account, uint48(timepoint)).toExternal();
    }

    function getTotalVotes() external view override returns (uint256) {
        return _$().checkpoints.currentTotal().toExternal();
    }

    function getPastTotalVotes(uint256 timepoint) external view override returns (uint256) {
        return _$().checkpoints.getTotal(uint48(timepoint)).toExternal();
    }

    function _delegate(Storage storage $, address delegator, address delegatee) internal override {
        Shares shares = $.sharesOf[delegator].load();
        address oldDelegatee = $.delegates[delegator];
        emit DelegateChanged(delegator, oldDelegatee, delegatee);
        $.delegates[delegator] = delegatee;
        Votes votes = shares.toVotes();
        $.checkpoints.transfer(oldDelegatee, delegatee, votes, votes, clock());
    }

    function _burn(Storage storage $, address from, CrazyBalance amount) internal override returns (bool) {
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }
        if (from == pair) {
            // `amount` is zero or we would not have passed `_checkAllowance`
            emit Transfer(from, address(0), 0);
            $.rebaseQueue.processQueue($.sharesOf, $.totalSupply, $.totalShares);
            return true;
        }

        (
            CrazyBalance balance,
            Shares originalShares,
            Shares cachedShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf($, from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newShares;
        Shares newTotalShares;
        Tokens newTotalSupply;
        if (amount == balance) {
            // The amount to be deducted from `_totalSupply` is *NOT* the same as
            // `amount.toTokens(from)`. That would not correctly account for dust that is below the
            // "crazy balance" scaling factor for `from`. We have to explicitly recompute the
            // un-crazy balance of `from` and deduct *THAT* instead.
            newTotalSupply = cachedTotalSupply - cachedShares.toTokens(cachedTotalSupply, cachedTotalShares);
            newTotalShares = cachedTotalShares - cachedShares;
            newShares = ZERO_SHARES;
        } else {
            (newShares, newTotalShares, newTotalSupply) =
                ReflectMath.getBurnShares(amount.toTokens(from), cachedTotalSupply, cachedTotalShares, cachedShares);
        }

        $.rebaseQueue.rebaseFor(from, cachedShares, cachedTotalSupply, cachedTotalShares);

        $.sharesOf[from] = newShares.store();
        $.totalShares = newTotalShares;
        $.totalSupply = newTotalSupply;
        emit Transfer(from, address(0), amount.toExternal());

        $.checkpoints.burn($.delegates[from], originalShares.toVotes() - newShares.toVotes(), clock());

        _pokeRebaseQueueFrom($, from, balance, amount, originalShares, newShares, newTotalSupply, newTotalShares);

        $.rebaseQueue.processQueue($.sharesOf, newTotalSupply, newTotalShares);

        return true;
    }

    function _deliver(Storage storage $, address from, CrazyBalance amount) internal override returns (bool) {
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }
        if (from == pair) {
            // `amount` is zero or we would not have passed `_checkAllowance`
            emit Transfer(from, address(0), 0);
            $.rebaseQueue.processQueue($.sharesOf, $.totalSupply, $.totalShares);
            return true;
        }

        (
            CrazyBalance balance,
            Shares originalShares,
            Shares cachedShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf($, from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newShares;
        Shares newTotalShares;
        if (amount == balance) {
            newTotalShares = cachedTotalShares - cachedShares;
            newShares = ZERO_SHARES;
        } else {
            (newShares, newTotalShares) =
                ReflectMath.getDeliverShares(amount.toTokens(from), cachedTotalSupply, cachedTotalShares, cachedShares);
        }

        $.rebaseQueue.rebaseFor(from, cachedShares, cachedTotalSupply, cachedTotalShares);

        $.sharesOf[from] = newShares.store();
        $.totalShares = newTotalShares;
        emit Transfer(from, address(0), amount.toExternal());

        $.checkpoints.burn($.delegates[from], originalShares.toVotes() - newShares.toVotes(), clock());

        _pokeRebaseQueueFrom($, from, balance, amount, originalShares, newShares, cachedTotalSupply, newTotalShares);

        $.rebaseQueue.processQueue($.sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }
}
