// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC2612} from "./interfaces/IERC2612.sol";
import {IERC5267} from "./interfaces/IERC5267.sol";
import {IERC5805} from "./interfaces/IERC5805.sol";
import {IERC6093} from "./interfaces/IERC6093.sol";
import {IERC7674} from "./interfaces/IERC7674.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";
import {CrazyBalance, toCrazyBalance, ZERO as ZERO_BALANCE, CrazyBalanceArithmetic} from "./core/CrazyBalance.sol";
import {TransientStorageLayout} from "./core/TransientStorageLayout.sol";
import {Checkpoints, LibCheckpoints} from "./core/Checkpoints.sol";

// TODO: move all user-defined types into ./types (instead of ./core/types)
import {BasisPoints, BASIS} from "./core/types/BasisPoints.sol";
import {Shares, ZERO as ZERO_SHARES, ONE as ONE_SHARE} from "./core/types/Shares.sol";
// TODO: rename Balance to Tokens (pretty big refactor)
import {Balance} from "./core/types/Balance.sol";
import {SharesToBalance} from "./core/types/BalanceXShares.sol";
import {Votes, toVotes} from "./core/types/Votes.sol";

import {Math} from "./lib/Math.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

contract FU is IERC2612, IERC5267, IERC5805, IERC6093, IERC7674, TransientStorageLayout {
    using ChecksumAddress for address;
    using {toCrazyBalance} for uint256;
    using SharesToBalance for Shares;
    using CrazyBalanceArithmetic for Shares;
    using CrazyBalanceArithmetic for CrazyBalance;
    using {toVotes} for Shares;
    using LibCheckpoints for Checkpoints;

    mapping(address account => Shares) internal _sharesOf;
    Balance internal _totalSupply;
    Shares internal _totalShares;
    mapping(address owner => mapping(address spender => CrazyBalance)) internal _allowance;
    mapping(address account => address) public override delegates;
    Checkpoints _checkpoints;
    mapping(address account => uint256) public override(IERC2612, IERC5805) nonces;

    function totalSupply() external view override returns (uint256) {
        return Balance.unwrap(_totalSupply);
    }

    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;

    // This mapping is actually in transient storage. It's placed here so that
    // solc reserves a slot for it during storage layout generation. Solc 0.8.28
    // doesn't support declaring mappings in transient storage. It is ultimately
    // manipulated by the `TransientStorageLayout` base contract (in assembly)
    mapping(address owner => mapping(address spender => CrazyBalance)) private _temporaryAllowance;

    constructor(address[] memory initialHolders) payable {
        require(_DOMAIN_TYPEHASH == keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
        require(_NAME_HASH == keccak256(bytes(name)));
        require(
            _PERMIT_TYPEHASH
                == keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
        );
        require(_DELEGATION_TYPEHASH == keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"));

        require(msg.value >= 1 ether);
        require(initialHolders.length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = pairFor(WETH, this);
        require(uint256(uint160(address(pair))) / Settings.ADDRESS_DIVISOR == 1);

        // slither-disable-next-line low-level-calls
        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));

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

        try FACTORY.createPair(WETH, IERC20(address(this))) returns (IUniswapV2Pair newPair) {
            require(pair == newPair);
        } catch {
            require(pair == FACTORY.getPair(WETH, IERC20(address(this))));
        }
        {
            (CrazyBalance pairBalance,,,,) = _balanceOf(address(pair));
            uint256 initialLiquidity = Math.sqrt(CrazyBalance.unwrap(pairBalance) * msg.value) - 1_000;
            require(pair.mint(address(0)) >= initialLiquidity);
        }
    }

    function _mintShares(address to, Shares shares) internal {
        Shares oldShares = _sharesOf[to];
        Shares newShares = oldShares + shares;
        _sharesOf[to] = newShares;
        emit Transfer(
            address(0),
            to,
            newShares.toCrazyBalance(address(type(uint160).max), _totalSupply, _totalShares).toExternal()
        );
    }

    function _check() internal view returns (bool) {
        return block.prevrandao & 1 == 0;
    }

    function _success() internal view returns (bool) {
        if (_check()) {
            assembly ("memory-safe") {
                stop()
            }
        }
        return true;
    }

    function _applyWhaleLimit(Shares shares, Shares totalShares_) internal pure returns (Shares, Shares) {
        Shares whaleLimit = totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        if (shares > whaleLimit) {
            whaleLimit = (totalShares_ - shares).div(Settings.ANTI_WHALE_DIVISOR - 1) - ONE_SHARE;
            totalShares_ = totalShares_ - (shares - whaleLimit);
            shares = whaleLimit;
        }
        return (shares, totalShares_);
    }

    function _applyWhaleLimit(Shares shares0, Shares shares1, Shares totalShares_)
        internal
        pure
        returns (Shares, Shares, Shares)
    {
        (shares0, shares1) = (shares0 > shares1) ? (shares0, shares1) : (shares1, shares0);
        Shares whaleLimit = totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE;
        if (shares0 > whaleLimit) {
            whaleLimit = (totalShares_ - shares0).div(Settings.ANTI_WHALE_DIVISOR - 1) - ONE_SHARE;
            if (shares1 > whaleLimit) {
                whaleLimit = (totalShares_ - shares0 - shares1).div(Settings.ANTI_WHALE_DIVISOR - 2) - ONE_SHARE;
                totalShares_ = totalShares_ - (shares0 + shares1 - whaleLimit.mul(2));
                shares0 = whaleLimit;
                shares1 = whaleLimit;
                // TODO: verify that this *EXACTLY* satisfied the postcondition `shares0 == shares1 == totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE`
            } else {
                totalShares_ = totalShares_ - (shares0 - whaleLimit);
                shares0 = whaleLimit;
            }
        }
        return (shares0, shares1, totalShares_);
    }

    function _loadAccount(address account) internal view returns (Shares, Shares, Shares) {
        if (account == address(pair)) {
            (Shares cachedAccountShares, Shares cachedTotalShares) = _applyWhaleLimit(_sharesOf[account], _totalShares);
            return (cachedAccountShares, cachedAccountShares, cachedTotalShares);
        }
        return _applyWhaleLimit(_sharesOf[account], _sharesOf[address(pair)], _totalShares);
    }

    function _balanceOf(address account) internal view returns (CrazyBalance, Shares, Shares, Balance, Shares) {
        (Shares cachedAccountShares, Shares cachedPairShares, Shares cachedTotalShares) = _loadAccount(account);
        Balance cachedTotalSupply = _totalSupply;
        CrazyBalance accountBalance = cachedAccountShares.toCrazyBalance(account, cachedTotalSupply, cachedTotalShares);
        return (accountBalance, cachedAccountShares, cachedPairShares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        (CrazyBalance balance,,,,) = _balanceOf(account);
        return balance.toExternal();
    }

    function _tax() internal view returns (BasisPoints) {
        // TODO: set tax to zero and prohibit `deliver` when the shares ratio gets to `Settings.MIN_SHARES_RATIO`
        revert("unimplemented");
    }

    function tax() external view returns (uint256) {
        return BasisPoints.unwrap(_tax());
    }

    function _transfer(address from, address to, CrazyBalance amount) internal returns (bool) {
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
                    ReflectMath.getTransferShares(taxRate, cachedTotalSupply, cachedTotalShares, cachedFromShares);
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

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (!_transfer(msg.sender, to, amount.toCrazyBalance())) {
            return false;
        }
        return _success();
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowance[msg.sender][spender] = amount.toCrazyBalance();
        emit Approval(msg.sender, spender, amount);
        return _success();
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        CrazyBalance temporaryAllowance = _getTemporaryAllowance(_temporaryAllowance, owner, spender);
        if (temporaryAllowance.isMax()) {
            return temporaryAllowance.toExternal();
        }
        return _allowance[owner][spender].saturatingAdd(temporaryAllowance).toExternal();
    }

    function _checkAllowance(address owner, CrazyBalance amount)
        internal
        view
        returns (bool, CrazyBalance, CrazyBalance)
    {
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
    ) internal {
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
        currentAllowance = currentAllowance - amount;
        _allowance[owner][msg.sender] = currentAllowance;
        emit Approval(owner, msg.sender, currentAllowance.toExternal());
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance(from, amount.toCrazyBalance());
        if (!success) {
            return false;
        }
        if (!_transfer(from, to, amount.toCrazyBalance())) {
            return false;
        }
        _spendAllowance(from, amount.toCrazyBalance(), currentTempAllowance, currentAllowance);
        return _success();
    }

    string public constant override name = "Fuck You!";

    function symbol() external view override returns (string memory) {
        if (msg.sender == tx.origin) {
            return "FU";
        }
        return string.concat("Fuck you, ", msg.sender.toChecksumAddress(), "!");
    }

    uint8 public constant override decimals = Settings.DECIMALS;

    bytes32 internal constant _DOMAIN_TYPEHASH = 0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866;
    bytes32 internal constant _NAME_HASH = 0xb614ddaf8c6c224524c95dbfcb82a82be086ec3a639808bbda893d5b4ac93694;

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() public view override returns (bytes32 r) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x00, _DOMAIN_TYPEHASH)
            mstore(0x20, _NAME_HASH)
            mstore(0x40, chainid())
            mstore(0x60, address())
            r := keccak256(0x00, 0x80)
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
    }

    bytes32 internal constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }
        uint256 nonce;
        unchecked {
            nonce = nonces[owner]++;
        }
        bytes32 sep = DOMAIN_SEPARATOR();
        address signer;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, _PERMIT_TYPEHASH)
            mstore(add(0x20, ptr), and(0xffffffffffffffffffffffffffffffffffffffff, owner))
            mstore(add(0x40, ptr), and(0xffffffffffffffffffffffffffffffffffffffff, spender))
            mstore(add(0x60, ptr), amount)
            mstore(add(0x80, ptr), nonce)
            mstore(add(0xa0, ptr), deadline)
            mstore(0x00, 0x1901)
            mstore(0x20, sep)
            mstore(0x40, keccak256(ptr, 0xc0))
            mstore(0x00, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            signer := mul(mload(0x00), staticcall(gas(), 0x01, 0x00, 0x80, 0x00, 0x20))
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }
        _allowance[owner][spender] = amount.toCrazyBalance();
        emit Approval(owner, spender, amount);
    }

    function eip712Domain()
        external
        view
        override
        returns (
            bytes1 fields,
            string memory name_,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        fields = bytes1(0x0d);
        name_ = name;
        chainId = block.chainid;
        verifyingContract = address(this);
    }

    function clock() public view override returns (uint48) {
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

    function _delegate(address delegator, address delegatee) internal {
        Shares shares = _sharesOf[delegator];
        address oldDelegatee = delegates[delegator];
        emit DelegateChanged(delegator, oldDelegatee, delegatee);
        delegates[delegator] = delegatee;
        Votes votes = shares.toVotes();
        _checkpoints.transfer(oldDelegatee, delegatee, votes, votes, clock());
    }

    function delegate(address delegatee) external override {
        return _delegate(msg.sender, delegatee);
    }

    bytes32 internal constant _DELEGATION_TYPEHASH = 0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf;

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        if (block.timestamp > expiry) {
            revert ERC5805ExpiredSignature(expiry);
        }
        bytes32 sep = DOMAIN_SEPARATOR();
        address signer;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x00, _DELEGATION_TYPEHASH)
            mstore(0x20, and(0xffffffffffffffffffffffffffffffffffffffff, delegatee))
            mstore(0x40, nonce)
            mstore(0x60, expiry)
            mstore(0x40, keccak256(0x00, 0x80))
            mstore(0x00, 0x1901)
            mstore(0x20, sep)
            mstore(0x00, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            signer := mul(mload(0x00), staticcall(gas(), 0x01, 0x00, 0x80, 0x00, 0x20))
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
        if (signer == address(0)) {
            revert ERC5805InvalidSignature();
        }
        unchecked {
            uint256 expected = nonces[signer]++;
            if (nonce != expected) {
                revert ERC5805InvalidNonce(nonce, expected);
            }
        }
        return _delegate(signer, delegatee);
    }

    function temporaryApprove(address spender, uint256 amount) external override returns (bool) {
        _setTemporaryAllowance(_temporaryAllowance, msg.sender, spender, amount.toCrazyBalance());
        return _success();
    }

    function _burn(address from, CrazyBalance amount) internal returns (bool) {
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
        } else {
            (newFromShares, newTotalShares, newTotalSupply) = ReflectMath.getBurnShares(
                amount.toBalance(from), cachedTotalSupply, cachedTotalShares, cachedFromShares
            );
        }
        _sharesOf[from] = newFromShares;
        (_sharesOf[address(pair)], _totalShares) = _applyWhaleLimit(cachedPairShares, newTotalShares);
        _totalSupply = newTotalSupply;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], cachedFromShares.toVotes() - newFromShares.toVotes(), clock());

        pair.sync();

        return true;
    }

    function burn(uint256 amount) external returns (bool) {
        if (!_burn(msg.sender, amount.toCrazyBalance())) {
            return false;
        }
        return _success();
    }

    function _deliver(address from, CrazyBalance amount) internal returns (bool) {
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
        Shares newTotalShares;
        if (amount == fromBalance) {
            newTotalShares = cachedTotalShares - cachedFromShares;
            newFromShares = ZERO_SHARES;
        } else if (cachedPairShares == totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - ONE_SHARE) {
            revert("unimplemented");
        } else {
            (newFromShares, newTotalShares) = ReflectMath.getDeliverShares(
                amount.toBalance(from), cachedTotalSupply, cachedTotalShares, cachedFromShares
            );
        }

        _sharesOf[from] = newFromShares;
        _sharesOf[address(pair)] = cachedPairShares;
        _totalShares = newTotalShares;
        emit Transfer(from, address(0), amount.toExternal());

        _checkpoints.burn(delegates[from], cachedFromShares.toVotes() - newFromShares.toVotes(), clock());

        pair.sync();

        return true;
    }

    function deliver(uint256 amount) external returns (bool) {
        if (!_deliver(msg.sender, amount.toCrazyBalance())) {
            return false;
        }
        return _success();
    }

    function burnFrom(address from, uint256 amount) external returns (bool) {
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance(from, amount.toCrazyBalance());
        if (!success) {
            return false;
        }
        if (!_burn(from, amount.toCrazyBalance())) {
            return false;
        }
        _spendAllowance(from, amount.toCrazyBalance(), currentTempAllowance, currentAllowance);
        return _success();
    }

    function deliverFrom(address from, uint256 amount) external returns (bool) {
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance(from, amount.toCrazyBalance());
        if (!success) {
            return false;
        }
        if (!_deliver(from, amount.toCrazyBalance())) {
            return false;
        }
        _spendAllowance(from, amount.toCrazyBalance(), currentTempAllowance, currentAllowance);
        return _success();
    }

    receive() external payable {
        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));
        pair.sync();
    }
}
