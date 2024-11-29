// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Base} from "./core/ERC20Base.sol";
import {FUStorage} from "./FUStorage.sol";

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";
import {TransientStorageLayout} from "./core/TransientStorageLayout.sol";
import {Checkpoints, LibCheckpoints} from "./core/Checkpoints.sol";

// TODO: move all user-defined types into ./types (instead of ./core/types)
import {BasisPoints} from "./core/types/BasisPoints.sol";
import {Shares, ZERO as ZERO_SHARES, ONE as ONE_SHARE} from "./core/types/Shares.sol";
// TODO: rename Balance to Tokens (pretty big refactor)
import {Balance} from "./core/types/Balance.sol";
import {SharesToBalance} from "./core/types/BalanceXShares.sol";
import {Votes, toVotes} from "./core/types/Votes.sol";
import {
    CrazyBalance,
    toCrazyBalance,
    ZERO as ZERO_BALANCE,
    MAX as MAX_BALANCE,
    CrazyBalanceArithmetic
} from "./core/CrazyBalance.sol";

import {Math} from "./lib/Math.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

contract FU is FUStorage, TransientStorageLayout, ERC20Base {
    using ChecksumAddress for address;
    using {toCrazyBalance} for uint256;
    using SharesToBalance for Shares;
    using CrazyBalanceArithmetic for Shares;
    using {toVotes} for Shares;
    using LibCheckpoints for Checkpoints;

    function totalSupply() external view override returns (uint256) {
        return Balance.unwrap(_totalSupply);
    }

    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;

    // This mapping is actually in transient storage. It's placed here so that
    // solc reserves a slot for it during storage layout generation. Solc 0.8.28
    // doesn't support declaring mappings in transient storage. It is ultimately
    // manipulated by the `TransientStorageLayout` base contract (in assembly)
    mapping(address owner => mapping(address spender => CrazyBalance allowed)) private _temporaryAllowance;

    constructor(address[] memory initialHolders) payable {
        require(Settings.SHARES_TO_VOTES_DIVISOR >= Settings.INITIAL_SHARES_RATIO);

        require(msg.value >= 1 ether);
        require(initialHolders.length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = pairFor(WETH, this);
        require(uint256(uint160(address(pair))) / Settings.ADDRESS_DIVISOR == 1);

        // slither-disable-next-line low-level-calls
        (bool success,) = address(WETH).call{value: address(this).balance}("");
        require(success);
        require(WETH.transfer(address(pair), WETH.balanceOf(address(this))));

        _totalSupply = Settings.INITIAL_SUPPLY;
        _totalShares = Settings.INITIAL_SHARES;
        _mintShares(DEAD, Settings.oneTokenInShares());
        _mintShares(address(pair), _totalShares.div(Settings.INITIAL_LIQUIDITY_DIVISOR));
        {
            Shares toMint = _totalShares - _sharesOf[DEAD] - _sharesOf[address(pair)];
            // slither-disable-next-line divide-before-multiply
            Shares toMintEach = toMint.div(initialHolders.length);
            _mintShares(initialHolders[0], toMint - toMintEach.mul(initialHolders.length - 1));
            for (uint256 i = 1; i < initialHolders.length; i++) {
                _mintShares(initialHolders[i], toMintEach);
            }
        }

        try FACTORY.createPair(WETH, this) returns (IUniswapV2Pair newPair) {
            require(pair == newPair);
        } catch {
            require(pair == FACTORY.getPair(WETH, this));
        }
        {
            (CrazyBalance pairBalance,,,,) = _balanceOf(address(pair));
            uint256 initialLiquidity =
                Math.sqrt(CrazyBalance.unwrap(pairBalance) * WETH.balanceOf(address(pair))) - 1_000;
            require(pair.mint(address(0)) >= initialLiquidity);
        }
    }

    function _consumeNonce(address account) internal override returns (uint256) {
        unchecked {
            return nonces[account]++;
        }
    }

    function _mintShares(address to, Shares shares) private {
        Shares oldShares = _sharesOf[to];
        Shares newShares = oldShares + shares;
        _sharesOf[to] = newShares;
        emit Transfer(
            address(0),
            to,
            newShares.toCrazyBalance(address(type(uint160).max), _totalSupply, _totalShares).toExternal()
        );
    }

    function _check() private view returns (bool) {
        return block.prevrandao & 1 == 0;
    }

    function _success() internal view override returns (bool) {
        if (_check()) {
            assembly ("memory-safe") {
                stop()
            }
        }
        return true;
    }

    function _applyWhaleLimit(Shares shares, Shares totalShares_) private pure returns (Shares, Shares) {
        Shares whaleLimit = totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        if (shares > whaleLimit) {
            whaleLimit = (totalShares_ - shares).div(Settings.ANTI_WHALE_DIVISOR - 1) - ONE_SHARE;
            totalShares_ = totalShares_ - (shares - whaleLimit);
            shares = whaleLimit;
        }
        return (shares, totalShares_);
    }

    // TODO: because we enforce as a postcondition of every function that pair is under the limit,
    // this function is kinda pointless
    function _applyWhaleLimit(Shares shares0, Shares shares1, Shares totalShares_)
        private
        pure
        returns (Shares, Shares, Shares)
    {
        (Shares sharesHi, Shares sharesLo) = (shares0 > shares1) ? (shares0, shares1) : (shares1, shares0);
        Shares whaleLimit = totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        if (sharesHi > whaleLimit) {
            whaleLimit = (totalShares_ - sharesHi).div(Settings.ANTI_WHALE_DIVISOR - 1) - ONE_SHARE;
            if (sharesLo > whaleLimit) {
                whaleLimit = (totalShares_ - sharesHi - sharesLo).div(Settings.ANTI_WHALE_DIVISOR - 2) - ONE_SHARE;
                totalShares_ = totalShares_ - (sharesHi + sharesLo - whaleLimit.mul(2));
                sharesHi = whaleLimit;
                sharesLo = whaleLimit;
                // TODO: verify that this *EXACTLY* satisfied the postcondition `sharesHi == sharesLo == totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE`
            } else {
                totalShares_ = totalShares_ - (sharesHi - whaleLimit);
                sharesHi = whaleLimit;
            }
        }
        (shares0, shares1) = (shares0 > shares1) ? (sharesHi, sharesLo) : (sharesLo, sharesHi);
        return (shares0, shares1, totalShares_);
    }

    function _loadAccount(address account) private view returns (Shares, Shares, Shares) {
        if (account == address(pair)) {
            (Shares cachedAccountShares, Shares cachedTotalShares) = _applyWhaleLimit(_sharesOf[account], _totalShares);
            return (cachedAccountShares, cachedAccountShares, cachedTotalShares);
        }
        return _applyWhaleLimit(_sharesOf[account], _sharesOf[address(pair)], _totalShares);
    }

    function _balanceOf(address account) private view returns (CrazyBalance, Shares, Shares, Balance, Shares) {
        (Shares cachedAccountShares, Shares cachedPairShares, Shares cachedTotalShares) = _loadAccount(account);
        Balance cachedTotalSupply = _totalSupply;
        CrazyBalance accountBalance = cachedAccountShares.toCrazyBalance(account, cachedTotalSupply, cachedTotalShares);
        return (accountBalance, cachedAccountShares, cachedPairShares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        (CrazyBalance balance,,,,) = _balanceOf(account);
        return balance.toExternal();
    }

    function _tax() private view returns (BasisPoints) {
        // TODO: set tax to zero and prohibit `deliver` when the shares ratio gets to `Settings.MIN_SHARES_RATIO`
        revert("unimplemented");
    }

    function tax() external view returns (uint256) {
        return BasisPoints.unwrap(_tax());
    }

    function _transfer(address from, address to, CrazyBalance amount) internal override returns (bool) {
        if (from == to) {
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }
        if (to == address(this)) {
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }
        if (uint256(uint160(to)) < Settings.ADDRESS_DIVISOR) {
            // "efficient" addresses can't hold tokens because they have zero multiplier
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }

        (
            CrazyBalance fromBalance,
            Shares cachedFromShares,
            Shares cachedPairShares,
            Balance cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from);

        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares cachedToShares;
        if (to == address(pair)) {
            cachedToShares = cachedPairShares;
        } else {
            cachedToShares = _sharesOf[to];
        }

        if (cachedToShares >= cachedTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            // Anti-whale (also because the reflection math breaks down)
            // We have to check this twice to ensure no underflow in the reflection math.  If `to ==
            // address(pair)` then we will implicitly pass this check due to applying the whale
            // limit when we loaded the accounts.
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }

        BasisPoints taxRate = _tax();
        Shares newFromShares;
        Shares newToShares;
        Shares newTotalShares;
        if (amount == fromBalance) {
            (newToShares, newTotalShares) = ReflectMath.getTransferShares(
                taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
            newFromShares = ZERO_SHARES;
        } else {
            (newFromShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                amount.toBalance(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
        }

        if (newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            if (to != address(pair)) {
                if (_check()) {
                    revert ERC20InvalidReceiver(to);
                }
                return false;
            }

            if (amount == fromBalance) {
                (cachedToShares, newToShares, newTotalShares) =
                    ReflectMath.getTransferShares(taxRate, cachedTotalShares, cachedFromShares);
                newFromShares = ZERO_SHARES;
            } else {
                (newFromShares, cachedToShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                    amount.toBalance(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares
                );
            }

        // === EFFECTS ARE ALLOWED ONLY FROM HERE DOWN ===

            // The quantity `cachedToShares` is counterfactual. We violate (temporarily) the
            // requirement that the sum of all accounts' shares equal the total shares. However,
            // this does mean that the balance of the pair increases between `sync()` and this
            // function's return by the requisite `amount * (1 - tax)`
            _sharesOf[to] = cachedToShares;
            // `pair` does not delegate, so we don't need to update any votes
            pair.sync();
        }

        {
            // Take note of the `to`/`from` mismatch here. We're converting `to`'s balance into
            // units as if it were held by `from`. Also note that when `to` is a whale, the `amount`
            // emitted in the event does not accurately reflect the change in balance.
            CrazyBalance transferAmount = newToShares.toCrazyBalance(from, cachedTotalSupply, newTotalShares)
                - cachedToShares.toCrazyBalance(from, cachedTotalSupply, cachedTotalShares);
            CrazyBalance burnAmount = amount - transferAmount;
            emit Transfer(from, to, transferAmount.toExternal());
            emit Transfer(from, address(0), burnAmount.toExternal());
        }
        _sharesOf[from] = newFromShares;

        // In these first two cases, the computation in `ReflectMath.getTransferShares` (whichever
        // version we used) enforces the postcondition that `from` and `to` come in under the whale
        // limit. So we don't need to check, we can just write the values to storage.
        if (from == address(pair)) {
            _sharesOf[to] = newToShares;
            _totalShares = newTotalShares;
            _checkpoints.mint(delegates[to], newToShares.toVotes() - cachedToShares.toVotes(), clock());
        } else if (to == address(pair)) {
            _sharesOf[to] = newToShares;
            _totalShares = newTotalShares;
            _checkpoints.burn(delegates[from], cachedFromShares.toVotes() - newFromShares.toVotes(), clock());
        } else {
            // However, in this last case, it's possible that because we burned some shares, `pair`
            // is now over the whale limit, even though we applied the limit when we loaded
            // it. Therefore, we have to apply the whale limit yet again.
            // TODO: what happens if `from` is a whale? could this push them over the limit?
            (_sharesOf[to], _sharesOf[address(pair)], _totalShares) =
                _applyWhaleLimit(newToShares, cachedPairShares, newTotalShares);
            _checkpoints.transfer(
                delegates[from],
                delegates[to],
                newToShares.toVotes() - cachedToShares.toVotes(),
                cachedFromShares.toVotes() - newFromShares.toVotes(),
                clock()
            );
            pair.sync();
        }

        return true;
    }

    function _approve(address owner, address spender, CrazyBalance amount) internal override {
        _allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount.toExternal());
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        if (spender == PERMIT2) {
            return type(uint256).max;
        }
        CrazyBalance temporaryAllowance = _getTemporaryAllowance(_temporaryAllowance, owner, spender);
        if (temporaryAllowance.isMax()) {
            return temporaryAllowance.toExternal();
        }
        return _allowance[owner][spender].saturatingAdd(temporaryAllowance).toExternal();
    }

    function _checkAllowance(address owner, CrazyBalance amount)
        internal
        view
        override
        returns (bool, CrazyBalance, CrazyBalance)
    {
        if (msg.sender == PERMIT2) {
            return (true, MAX_BALANCE, ZERO_BALANCE);
        }
        CrazyBalance currentTempAllowance = _getTemporaryAllowance(_temporaryAllowance, owner, msg.sender);
        if (currentTempAllowance >= amount) {
            return (true, currentTempAllowance, ZERO_BALANCE);
        }
        CrazyBalance currentAllowance = _allowance[owner][msg.sender];
        if (currentAllowance >= amount - currentTempAllowance) {
            return (true, currentTempAllowance, currentAllowance);
        }
        if (_check()) {
            revert ERC20InsufficientAllowance(msg.sender, currentAllowance.toExternal(), amount.toExternal());
        }
        return (false, ZERO_BALANCE, ZERO_BALANCE);
    }

    function _spendAllowance(
        address owner,
        CrazyBalance amount,
        CrazyBalance currentTempAllowance,
        CrazyBalance currentAllowance
    ) internal override {
        if (currentTempAllowance.isMax()) {
            // TODO: maybe remove this branch
            return;
        }
        if (currentAllowance == ZERO_BALANCE) {
            _setTemporaryAllowance(_temporaryAllowance, owner, msg.sender, currentTempAllowance - amount);
            return;
        }
        if (currentTempAllowance != ZERO_BALANCE) {
            amount = amount - currentTempAllowance;
            _setTemporaryAllowance(_temporaryAllowance, owner, msg.sender, ZERO_BALANCE);
        }
        if (currentAllowance.isMax()) {
            return;
        }
        _approve(owner, msg.sender, currentAllowance - amount);
    }

    function name() public pure override returns (string memory) {
        return "Fuck You!";
    }

    function symbol() external view override returns (string memory r) {
        if (msg.sender == tx.origin) {
            return "FU";
        }
        assembly ("memory-safe") {
            r := mload(0x40)
            mstore(0x40, add(0x0a, r))
        }
        msg.sender.toChecksumAddress();
        assembly ("memory-safe") {
            mstore(add(0x0a, r), 0x4675636b20796f752c20)
            mstore(r, 0x35)
            mstore8(add(0x54, r), 0x21)
        }
    }

    uint8 public constant override decimals = Settings.DECIMALS;

    function _NAME_HASH() internal pure override returns (bytes32) {
        return 0xb614ddaf8c6c224524c95dbfcb82a82be086ec3a639808bbda893d5b4ac93694;
    }

    function clock() public view override(IERC6372, ERC20Base) returns (uint48) {
        unchecked {
            // slither-disable-next-line divide-before-multiply
            return uint48(block.timestamp / 1 days * 1 days);
        }
    }

    // slither-disable-next-line naming-convention
    string public constant override CLOCK_MODE = "mode=timestamp&epoch=1970-01-01T00%3A00%3A00Z&quantum=86400";

    function getVotes(address account) external view override returns (uint256) {
        return _checkpoints.current(account).toExternal();
    }

    function getPastVotes(address account, uint256 timepoint) external view override returns (uint256) {
        return _checkpoints.get(account, uint48(timepoint)).toExternal();
    }

    function getTotalVotes() external view returns (uint256) {
        return _checkpoints.currentTotal().toExternal();
    }

    function getPastTotalVotes(uint256 timepoint) external view returns (uint256) {
        return _checkpoints.getTotal(uint48(timepoint)).toExternal();
    }

    function _delegate(address delegator, address delegatee) internal override {
        Shares shares = _sharesOf[delegator];
        address oldDelegatee = delegates[delegator];
        emit DelegateChanged(delegator, oldDelegatee, delegatee);
        delegates[delegator] = delegatee;
        Votes votes = shares.toVotes();
        _checkpoints.transfer(oldDelegatee, delegatee, votes, votes, clock());
    }

    function temporaryApprove(address spender, uint256 amount) external override returns (bool) {
        _setTemporaryAllowance(_temporaryAllowance, msg.sender, spender, amount.toCrazyBalance());
        return _success();
    }

    function _burn(address from, CrazyBalance amount) internal override returns (bool) {
        (
            CrazyBalance fromBalance,
            Shares cachedFromShares,
            Shares cachedPairShares,
            Balance cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from);
        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newFromShares;
        Shares newPairShares = cachedPairShares;
        Shares newTotalShares;
        Balance newTotalSupply;
        if (amount == fromBalance) {
            // The amount to be deducted from `_totalSupply` is *NOT* the same as
            // `amount.toBalance(from)`. That would not correctly account for dust that is below the
            // "crazy balance" scaling factor for `from`. We have to explicitly recompute the
            // un-crazy balance of `from` and deduct *THAT* instead.
            newTotalSupply = cachedTotalSupply - cachedFromShares.toBalance(cachedTotalSupply, cachedTotalShares);
            newTotalShares = cachedTotalShares - cachedFromShares;
            newFromShares = ZERO_SHARES;
            (newPairShares, newTotalShares) = _applyWhaleLimit(newPairShares, newTotalShares);
        } else {
            Balance amountUnCrazy = amount.toBalance(from);
            newFromShares =
                ReflectMath.getBurnShares(amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares);
            newTotalShares = newTotalShares - (cachedFromShares - newFromShares);
            newTotalSupply = cachedTotalSupply - amountUnCrazy;
            if (newPairShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
                (newFromShares, newTotalShares) = ReflectMath.getBurnSharesPairWhale(
                    amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares
                );
                newPairShares = newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
            }
        }

        _sharesOf[from] = newFromShares;
        _totalShares = newTotalShares;
        _totalSupply = newTotalSupply;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], cachedFromShares.toVotes() - newFromShares.toVotes(), clock());

        if (newPairShares != cachedPairShares) {
            _sharesOf[address(pair)] = newPairShares;
            pair.sync();
        }

        return true;
    }

    function _deliver(address from, CrazyBalance amount) internal override returns (bool) {
        (
            CrazyBalance fromBalance,
            Shares cachedFromShares,
            Shares cachedPairShares,
            Balance cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from);
        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newFromShares;
        Shares newPairShares = cachedPairShares;
        Shares newTotalShares;
        if (amount == fromBalance) {
            newTotalShares = cachedTotalShares - cachedFromShares;
            newFromShares = ZERO_SHARES;
            (newPairShares, newTotalShares) = _applyWhaleLimit(newPairShares, newTotalShares);
        } else {
            Balance amountUnCrazy = amount.toBalance(from);
            (newFromShares, newTotalShares) =
                ReflectMath.getDeliverShares(amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares);
            if (newPairShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
                (newFromShares, newTotalShares) = ReflectMath.getDeliverSharesPairWhale(
                    amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares
                );
                newPairShares = newTotalShares.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
            }
        }

        _sharesOf[from] = newFromShares;
        _totalShares = newTotalShares;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], cachedFromShares.toVotes() - newFromShares.toVotes(), clock());

        if (newPairShares != cachedPairShares) {
            _sharesOf[address(pair)] = cachedPairShares;
            pair.sync();
        }

        return true;
    }

    receive() external payable {
        (bool success,) = address(WETH).call{value: address(this).balance}("");
        require(success);
        require(WETH.transfer(address(pair), WETH.balanceOf(address(this))));
        pair.sync();
    }
}
