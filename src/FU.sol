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
import {RebaseQueue, LibRebaseQueue} from "./core/RebaseQueue.sol";

import {BasisPoints, BASIS} from "./types/BasisPoints.sol";
import {Shares, ZERO as ZERO_SHARES, ONE as ONE_SHARE} from "./types/Shares.sol";
import {Tokens} from "./types/Tokens.sol";
import {SharesToTokens} from "./types/TokensXShares.sol";
import {SharesToTokensProportional} from "./types/TokensXBasisPointsXShares.sol";
import {Votes, toVotes} from "./types/Votes.sol";
import {SharesXBasisPoints, scale} from "./types/SharesXBasisPoints.sol";
import {
    CrazyBalance,
    toCrazyBalance,
    ZERO as ZERO_BALANCE,
    MAX as MAX_BALANCE,
    CrazyBalanceArithmetic
} from "./types/CrazyBalance.sol";

import {Math} from "./lib/Math.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";
import {IPFS} from "./lib/IPFS.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

contract FU is FUStorage, TransientStorageLayout, ERC20Base {
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

    function totalSupply() external view override returns (uint256) {
        unchecked {
            return Tokens.unwrap(_totalSupply + _pairTokens);
        }
    }

    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;

    bytes32 internal immutable _logoHash;

    function tokenURI() external view override returns (string memory) {
        return _logoHash.CIDv0();
    }

    // This mapping is actually in transient storage. It's placed here so that
    // solc reserves a slot for it during storage layout generation. Solc 0.8.28
    // doesn't support declaring mappings in transient storage. It is ultimately
    // manipulated by the `TransientStorageLayout` base contract (in assembly)
    mapping(address owner => mapping(address spender => CrazyBalance allowed)) private _temporaryAllowance;

    event GitCommit(bytes20 indexed gitCommit);

    constructor(bytes20 gitCommit, string memory logo, address[] memory initialHolders) payable {
        require(Settings.SHARES_TO_VOTES_DIVISOR >= Settings.INITIAL_SHARES_RATIO);

        require(msg.sender == 0x4e59b44847b379578588920cA78FbF26c0B4956C);
        require(msg.value >= 1 ether);
        require(initialHolders.length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = pairFor(WETH, this);
        require(uint256(uint160(address(pair))) / Settings.ADDRESS_DIVISOR == 1);

        assembly ("memory-safe") {
            log0(add(0x20, logo), mload(logo))
        }
        emit GitCommit(gitCommit);
        _logoHash = logo.dagPbUnixFsHash();

        // slither-disable-next-line low-level-calls
        (bool success,) = address(WETH).call{value: address(this).balance}("");
        require(success);
        require(WETH.transfer(address(pair), WETH.balanceOf(address(this))));

        Tokens pairTokens = Settings.INITIAL_SUPPLY.div(Settings.INITIAL_LIQUIDITY_DIVISOR);
        pairTokens = pairTokens - Tokens.wrap(Tokens.unwrap(pairTokens) % Settings.CRAZY_BALANCE_BASIS);
        _pairTokens = pairTokens;
        emit Transfer(address(0), address(pair), Tokens.unwrap(pairTokens));

        Tokens totalSupply_ = Settings.INITIAL_SUPPLY - pairTokens;
        _totalSupply = totalSupply_;
        Shares totalShares = Shares.wrap(Tokens.unwrap(totalSupply_) * Settings.INITIAL_SHARES_RATIO);
        _totalShares = totalShares;

        {
            // The queue is empty, so we have to special-case the first insertion. `DEAD` will
            // always hold a token balance, which makes many things simpler.
            _sharesOf[DEAD] = Settings.oneTokenInShares();
            CrazyBalance balance = _sharesOf[DEAD].toCrazyBalance(totalSupply_, totalShares);
            emit Transfer(address(0), DEAD, balance.toExternal());
            _rebaseQueue.initialize(DEAD, balance);
        }
        {
            Shares toMint = totalShares - _sharesOf[DEAD];
            // slither-disable-next-line divide-before-multiply
            Shares sharesRest = toMint.div(initialHolders.length);
            {
                Shares sharesFirst = toMint - sharesRest.mul(initialHolders.length - 1);
                CrazyBalance amount = sharesFirst.toCrazyBalance(totalSupply_, totalShares);

                address to = initialHolders[0];
                assert(_sharesOf[to] == ZERO_SHARES);
                _sharesOf[to] = sharesFirst;
                emit Transfer(address(0), to, amount.toExternal());
                _rebaseQueue.enqueue(to, amount);
            }
            {
                CrazyBalance amount = sharesRest.toCrazyBalance(totalSupply_, totalShares);
                for (uint256 i = 1; i < initialHolders.length; i++) {
                    address to = initialHolders[i];
                    assert(_sharesOf[to] == ZERO_SHARES);
                    _sharesOf[to] = sharesRest;
                    emit Transfer(address(0), to, amount.toExternal());
                    _rebaseQueue.enqueue(to, amount);
                }
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

    function _check() private view returns (bool) {
        return block.prevrandao & 1 == 1;
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

    function _loadAccount(address account)
        private
        view
        returns (Shares originalShares, Shares cachedShares, Shares cachedTotalShares)
    {
        originalShares = _sharesOf[account];
        (cachedShares, cachedTotalShares) = _applyWhaleLimit(originalShares, _totalShares);
    }

    function _loadAccounts(address account0, address account1)
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
        originalShares0 = _sharesOf[account0];
        originalShares1 = _sharesOf[account1];
        (cachedShares0, cachedShares1, cachedTotalShares) =
            _applyWhaleLimit(originalShares0, originalShares1, _totalShares);
    }

    function _balanceOf(address account)
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
        (originalShares, cachedShares, cachedTotalShares) = _loadAccount(account);
        cachedTotalSupply = _totalSupply;
        balance = cachedShares.toCrazyBalance(account, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        if (account == address(pair)) {
            return _pairTokens.toPairBalance().toExternal();
        }
        (CrazyBalance balance,,,,) = _balanceOf(account);
        return balance.toExternal();
    }

    function _balanceOf(address account0, address account1)
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
            _loadAccounts(account0, account1);
        cachedTotalSupply = _totalSupply;
        balance0 = cachedShares0.toCrazyBalance(account0, cachedTotalSupply, cachedTotalShares);
    }

    function _tax() private view returns (BasisPoints) {
        revert("unimplemented");
    }

    function tax() external view returns (uint256) {
        return BasisPoints.unwrap(_tax());
    }

    function _transferFromPair(address to, CrazyBalance amount) private returns (bool) {
        // We don't need to check that `pair` is transferring less than its balance. The
        // `UniswapV2Pair` code does that for us. Additionally, `pair`'s balance can never reach
        // zero.

        BasisPoints taxRate = _tax();
        (Shares originalShares, Shares cachedShares, Shares cachedTotalShares) = _loadAccount(to);
        Tokens cachedTotalSupply = _totalSupply;
        Tokens amountTokens = amount.toPairTokens();

        (Shares newShares, Shares newTotalShares) = ReflectMath.getTransferShares(
            taxRate, cachedTotalSupply, cachedTotalShares, amount.toPairTokens(), cachedShares
        );
        Tokens newTotalSupply = cachedTotalSupply + amountTokens;

        // TODO: specialize `toCrazyBalance`
        CrazyBalance transferAmount = newShares.toCrazyBalance(address(pair), newTotalSupply, newTotalShares)
            - cachedTotalShares.toCrazyBalance(address(pair), cachedTotalSupply, cachedTotalShares);
        CrazyBalance burnAmount = amount - transferAmount;

        (newShares, newTotalShares) = _applyWhaleLimit(newShares, newTotalShares);

        _rebaseQueue.rebaseFor(to, cachedShares, cachedTotalSupply, cachedTotalShares);

        _pairTokens = _pairTokens - amountTokens;
        _sharesOf[to] = newShares;
        _totalSupply = newTotalSupply;
        _totalShares = newTotalShares;

        emit Transfer(address(pair), to, transferAmount.toExternal());
        emit Transfer(address(pair), address(0), burnAmount.toExternal());

        if (newShares >= originalShares) {
            _checkpoints.mint(delegates[to], newShares.toVotes() - originalShares.toVotes(), clock());
        } else {
            _checkpoints.burn(delegates[to], originalShares.toVotes() - newShares.toVotes(), clock());
        }

        if (originalShares == ZERO_SHARES) {
            _rebaseQueue.enqueue(to, newShares, newTotalSupply, newTotalShares);
        } else {
            _rebaseQueue.moveToBack(to, newShares, newTotalSupply, newTotalShares);
        }

        _rebaseQueue.processQueue(_sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }

    function _transferToPair(address from, CrazyBalance amount) private returns (bool) {
        revert("unimplemented");
        /*
            _rebaseQueue.rebaseFor(from, cachedFromShares, cachedTotalSupply, cachedTotalShares);

            _sharesOf[from] = newFromShares;
            _sharesOf[to] = newToShares;
            _totalShares = newTotalShares;
            emit Transfer(from, to, transferAmount.toExternal());
            emit Transfer(from, address(0), burnAmount.toExternal());

            _checkpoints.burn(delegates[from], originalFromShares.toVotes() - newFromShares.toVotes(), clock());

            if (amount == fromBalance) {
                _rebaseQueue.dequeue(from);
            } else {
                _rebaseQueue.moveToBack(from, newFromShares, cachedTotalSupply, newTotalShares);
            }

            _rebaseQueue.processQueue(_sharesOf, cachedTotalSupply, newTotalShares);

            return true;
        */
    }

    function _transfer(address from, address to, CrazyBalance amount) internal override returns (bool) {
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }
        if (from == to) {
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }
        if (to == DEAD) {
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

        if (from == address(pair)) {
            return _transferFromPair(to, amount);
        }
        if (to == address(pair)) {
            return _transferToPair(from, amount);
        }

        (
            CrazyBalance fromBalance,
            Shares originalFromShares,
            Shares cachedFromShares,
            Shares originalToShares,
            Shares cachedToShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from, to);

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
                taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
            newFromShares = ZERO_SHARES;
        } else {
            (newFromShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                amount.toTokens(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
        }

        if (newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            if (amount == fromBalance) {
                (cachedToShares, newToShares, newTotalShares) =
                    ReflectMath.getTransferShares(taxRate, cachedTotalShares, cachedFromShares);
                newFromShares = ZERO_SHARES;
            } else {
                (newFromShares, cachedToShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                    amount.toTokens(from), taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares
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

        // The computation in `ReflectMath.getTransferShares` (whichever version we used) enforces
        // the postcondition that `from` and `to` come in under the whale limit. So we don't need to
        // check, we can just write the values to storage.
        _rebaseQueue.rebaseFor(from, cachedFromShares, cachedTotalSupply, cachedTotalShares);
        _rebaseQueue.rebaseFor(to, cachedToShares, cachedTotalSupply, cachedTotalShares);

        _sharesOf[from] = newFromShares;
        _sharesOf[to] = newToShares;
        _totalShares = newTotalShares;
        emit Transfer(from, to, transferAmount.toExternal());
        emit Transfer(from, address(0), burnAmount.toExternal());

        if (newToShares >= originalToShares) {
            _checkpoints.transfer(
                delegates[from],
                delegates[to],
                newToShares.toVotes() - originalToShares.toVotes(),
                originalFromShares.toVotes() - newFromShares.toVotes(),
                clock()
            );
        } else {
            _checkpoints.burn(delegates[from], originalFromShares.toVotes() - newFromShares.toVotes(), clock());
            _checkpoints.burn(delegates[to], originalToShares.toVotes() - newToShares.toVotes(), clock());
        }

        if (originalToShares == ZERO_SHARES) {
            _rebaseQueue.enqueue(to, newToShares, cachedTotalSupply, newTotalShares);
        } else {
            _rebaseQueue.moveToBack(to, newToShares, cachedTotalSupply, newTotalShares);
        }

        if (amount == fromBalance) {
            _rebaseQueue.dequeue(from);
        } else {
            _rebaseQueue.moveToBack(from, newFromShares, cachedTotalSupply, newTotalShares);
        }

        _rebaseQueue.processQueue(_sharesOf, cachedTotalSupply, newTotalShares);

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
            mstore(0x40, add(0x60, r))
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
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }

        (
            CrazyBalance fromBalance,
            Shares originalFromShares,
            Shares cachedFromShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from);
        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newFromShares;
        Shares newTotalShares;
        Tokens newTotalSupply;
        if (amount == fromBalance) {
            // The amount to be deducted from `_totalSupply` is *NOT* the same as
            // `amount.toTokens(from)`. That would not correctly account for dust that is below the
            // "crazy balance" scaling factor for `from`. We have to explicitly recompute the
            // un-crazy balance of `from` and deduct *THAT* instead.
            newTotalSupply = cachedTotalSupply - cachedFromShares.toTokens(cachedTotalSupply, cachedTotalShares);
            newTotalShares = cachedTotalShares - cachedFromShares;
            newFromShares = ZERO_SHARES;
        } else {
            Tokens amountUnCrazy = amount.toTokens(from);
            newFromShares =
                ReflectMath.getBurnShares(amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares);
            newTotalShares = newTotalShares - (cachedFromShares - newFromShares);
            newTotalSupply = cachedTotalSupply - amountUnCrazy;
        }

        _rebaseQueue.rebaseFor(from, cachedFromShares, cachedTotalSupply, cachedTotalShares);

        _sharesOf[from] = newFromShares;
        _totalShares = newTotalShares;
        _totalSupply = newTotalSupply;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], originalFromShares.toVotes() - newFromShares.toVotes(), clock());

        if (amount == fromBalance) {
            _rebaseQueue.dequeue(from);
        } else {
            _rebaseQueue.moveToBack(from, newFromShares, newTotalSupply, newTotalShares);
        }

        _rebaseQueue.processQueue(_sharesOf, newTotalSupply, newTotalShares);

        return true;
    }

    function _deliver(address from, CrazyBalance amount) internal override returns (bool) {
        if (from == DEAD) {
            if (_check()) {
                revert ERC20InvalidSender(from);
            }
            return false;
        }

        (
            CrazyBalance fromBalance,
            Shares originalFromShares,
            Shares cachedFromShares,
            Tokens cachedTotalSupply,
            Shares cachedTotalShares
        ) = _balanceOf(from);
        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares newFromShares;
        Shares newTotalShares;
        if (amount == fromBalance) {
            newTotalShares = cachedTotalShares - cachedFromShares;
            newFromShares = ZERO_SHARES;
        } else {
            Tokens amountUnCrazy = amount.toTokens(from);
            (newFromShares, newTotalShares) =
                ReflectMath.getDeliverShares(amountUnCrazy, cachedTotalSupply, cachedTotalShares, cachedFromShares);
        }

        _rebaseQueue.rebaseFor(from, cachedFromShares, cachedTotalSupply, cachedTotalShares);

        _sharesOf[from] = newFromShares;
        _totalShares = newTotalShares;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], originalFromShares.toVotes() - newFromShares.toVotes(), clock());

        if (amount == fromBalance) {
            _rebaseQueue.dequeue(from);
        } else {
            _rebaseQueue.moveToBack(from, newFromShares, cachedTotalSupply, newTotalShares);
        }

        _rebaseQueue.processQueue(_sharesOf, cachedTotalSupply, newTotalShares);

        return true;
    }

    receive() external payable {
        (bool success,) = address(WETH).call{value: address(this).balance}("");
        require(success);
        require(WETH.transfer(address(pair), WETH.balanceOf(address(this))));
        pair.sync();
    }
}
