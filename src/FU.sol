// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC2612} from "./interfaces/IERC2612.sol";
import {IERC5267} from "./interfaces/IERC5267.sol";
import {IERC6093} from "./interfaces/IERC6093.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";
import {IERC7674} from "./interfaces/IERC7674.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";
import {CrazyBalance, fromExternal, ZERO as ZERO_BALANCE, CrazyBalanceArithmetic} from "./core/CrazyBalance.sol";
import {TransientStorageLayout} from "./core/TransientStorageLayout.sol";

// TODO: move all user-defined types into ./types (instead of ./core/types)
import {BasisPoints, BASIS} from "./core/types/BasisPoints.sol";
import {Shares, ZERO as ZERO_SHARES, ONE as ONE_SHARE} from "./core/types/Shares.sol";
// TODO: rename Balance to Tokens (pretty big refactor)
import {Balance} from "./core/types/Balance.sol";
import {SharesToBalance} from "./core/types/BalanceXShares.sol";

import {Math} from "./lib/Math.sol";
import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

contract FU is IERC2612, IERC5267, IERC6093, IERC6372, IERC7674, TransientStorageLayout {
    using UnsafeMath for uint256;
    using ChecksumAddress for address;
    using {fromExternal} for uint256;
    using SharesToBalance for Shares;
    using CrazyBalanceArithmetic for Shares;
    using CrazyBalanceArithmetic for CrazyBalance;

    // TODO: use a user-defined type to separate shares-denominated values from balance-denominated values
    mapping(address => Shares) internal _sharesOf;
    mapping(address => uint256) public override nonces;
    mapping(address => mapping(address => CrazyBalance)) internal _allowance;
    Balance internal _totalSupply;
    Shares internal _totalShares;
    /// @custom:security non-reentrant
    IUniswapV2Pair public immutable pair;

    function totalSupply() external view override returns (uint256) {
        return Balance.unwrap(_totalSupply);
    }

    // TODO: maybe we shouldn't expose these two functions? They're an abstraction leak
    function sharesOf(address account) external view returns (uint256) {
        return Shares.unwrap(_sharesOf[account]);
    }

    function totalShares() external view returns (uint256) {
        return Shares.unwrap(_totalShares);
    }

    // This mapping is actually in transient storage. It's placed here so that
    // solc reserves a slot for it during storage layout generation. Solc 0.8.28
    // doesn't support declaring mappings in transient storage. It is ultimately
    // manipulated by the TransientStorageLayout base contract (in assembly)
    mapping(address => mapping(address => CrazyBalance)) private _temporaryAllowance;

    constructor(address[] memory initialHolders) payable {
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
        require(pair.mint(address(0)) >= Math.sqrt(Balance.unwrap(Settings.INITIAL_SUPPLY.div(Settings.INITIAL_LIQUIDITY_DIVISOR)) * 1 ether) - 1_000);
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
            totalShares_ = totalShares_ - (shares - whaleLimit);
            shares = whaleLimit;
        }
        return (shares, totalShares_);
    }

    function _loadAccount(address account) internal view returns (Shares, Shares) {
        return _applyWhaleLimit(_sharesOf[account], _totalShares);
    }

    function _balanceOf(address account) internal view returns (CrazyBalance, Shares, Balance, Shares) {
        (Shares shares, Shares cachedTotalShares) = _loadAccount(account);
        Balance cachedTotalSupply = _totalSupply;
        CrazyBalance balance = shares.toCrazyBalance(account, cachedTotalSupply, cachedTotalShares);
        return (balance, shares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        (CrazyBalance balance,,,) = _balanceOf(account);
        return balance.toExternal();
    }

    function _fee() internal view returns (BasisPoints) {
        // TODO: set fee to zero and prohibit `deliver` when the shares ratio gets to `Settings.MIN_SHARES_RATIO`
        revert("unimplemented");
    }

    function fee() external view returns (uint256) {
        return BasisPoints.unwrap(_fee());
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

        (CrazyBalance fromBalance, Shares cachedFromShares, Balance cachedTotalSupply, Shares cachedTotalShares) =
            _balanceOf(from);

        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        Shares cachedToShares = _sharesOf[to];
        if (to == address(pair)) {
            (cachedToShares, cachedTotalShares) = _applyWhaleLimit(cachedToShares, cachedTotalShares);
        }

        if (cachedToShares >= cachedTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            // anti-whale (also because the reflection math breaks down)
            // we have to check this twice to ensure no underflow in the reflection math
            if (_check()) {
                revert ERC20InvalidReceiver(to);
            }
            return false;
        }

        BasisPoints feeRate = _fee();
        Shares newFromShares;
        Shares newToShares;
        Shares newTotalShares;
        if (amount == fromBalance) {
            (newToShares, newTotalShares) = ReflectMath.getTransferShares(
                feeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
            newFromShares = ZERO_SHARES;
        } else {
            (newFromShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                amount.toBalance(from), feeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
        }

        if (newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            if (to != address(pair)) {
                if (_check()) {
                    // TODO: maybe make this a new error? It's not exactly an invalid recipient, it's an
                    // invalid (too high) transfer amount
                    revert ERC20InvalidReceiver(to);
                }
                return false;
            }

        // === EFFECTS ARE ALLOWED ONLY FROM HERE DOWN ===
            CrazyBalance oldPairBalance = cachedToShares.toCrazyBalance(to, cachedTotalSupply, cachedTotalShares);
            (cachedToShares, cachedTotalShares, cachedTotalSupply) = ReflectMath.getBurnShares(
                amount.toBalance(from, BASIS - feeRate), cachedTotalSupply, cachedTotalShares, cachedToShares
            );

            emit Transfer(
                to,
                address(0),
                (oldPairBalance - cachedToShares.toCrazyBalance(to, cachedTotalSupply, cachedTotalShares)).toExternal()
            );
            _sharesOf[to] = cachedToShares;
            _totalShares = cachedTotalShares;
            _totalSupply = cachedTotalSupply;

            pair.sync();

            if (amount == fromBalance) {
                (newToShares, newTotalShares) = ReflectMath.getTransferShares(
                    feeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
                );
                newFromShares = ZERO_SHARES;
            } else {
                (newFromShares, newToShares, newTotalShares) = ReflectMath.getTransferShares(
                    amount.toBalance(from),
                    feeRate,
                    cachedTotalSupply,
                    cachedTotalShares,
                    cachedFromShares,
                    cachedToShares
                );
            }
        }

        {
            // Take note of the `to`/`from` mismatch here. We're converting `to`'s balance into
            // units as if it were held by `from`
            // TODO: this first `toCrazyBalance` could probably be combined/computed with `ReflectMath.getTransferShares`
            CrazyBalance transferAmount = newToShares.toCrazyBalance(from, cachedTotalSupply, newTotalShares)
                - cachedToShares.toCrazyBalance(from, cachedTotalSupply, cachedTotalShares);
            CrazyBalance burnAmount = amount - transferAmount;
            emit Transfer(from, to, transferAmount.toExternal());
            emit Transfer(from, address(0), burnAmount.toExternal());
        }
        _sharesOf[from] = newFromShares;
        _sharesOf[to] = newToShares;
        _totalShares = newTotalShares;

        if (!(from == address(pair) || to == address(pair))) {
            pair.sync();
        }

        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (!_transfer(msg.sender, to, amount.fromExternal())) {
            return false;
        }
        return _success();
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowance[msg.sender][spender] = amount.fromExternal();
        emit Approval(msg.sender, spender, amount);
        return _success();
    }

    function allowance(address owner, address spender) external view returns (uint256) {
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
            _checkAllowance(from, amount.fromExternal());
        if (!success) {
            return false;
        }
        if (!_transfer(from, to, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount.fromExternal(), currentTempAllowance, currentAllowance);
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

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                block.chainid,
                address(this)
            )
        );
    }

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
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                amount,
                nonces[owner]++,
                deadline
            )
        );
        bytes32 signingHash = keccak256(abi.encodePacked(bytes2(0x1901), DOMAIN_SEPARATOR(), structHash));
        address signer = ecrecover(signingHash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }
        _allowance[owner][spender] = amount.fromExternal();
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
        return uint48(block.timestamp / 86400 * 86400);
    }

    // slither-disable-next-line naming-convention
    string public constant override CLOCK_MODE = "mode=timestamp&epoch=1970-01-01T00%3A00%3A00Z&quantum=86400";

    function temporaryApprove(address spender, uint256 amount) external override returns (bool) {
        _setTemporaryAllowance(_temporaryAllowance, msg.sender, spender, amount.fromExternal());
        return _success();
    }

    function _burn(address from, CrazyBalance amount) internal returns (bool) {
        (CrazyBalance balance, Shares shares, Balance cachedTotalSupply, Shares cachedTotalShares) = _balanceOf(from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        if (amount == balance) {
            // The amount to be deducted from `_totalSupply` is *NOT* the same as
            // `amount.toBalance(from)`. That would not correctly account for dust that is below the
            // "crazy balance" scaling factor for `from`. We have to explicitly recompute the
            // un-crazy balance of `from` and deduct *THAT* instead.
            cachedTotalSupply = cachedTotalSupply - shares.toBalance(cachedTotalSupply, cachedTotalShares);
            cachedTotalShares = cachedTotalShares - shares;
            shares = ZERO_SHARES;
        } else {
            (shares, cachedTotalShares, cachedTotalSupply) =
                ReflectMath.getBurnShares(amount.toBalance(from), cachedTotalSupply, cachedTotalShares, shares);
        }
        _sharesOf[from] = shares;
        _totalShares = cachedTotalShares;
        _totalSupply = cachedTotalSupply;
        emit Transfer(from, address(0), amount.toExternal());

        pair.sync();

        return true;
    }

    function burn(uint256 amount) external returns (bool) {
        if (!_burn(msg.sender, amount.fromExternal())) {
            return false;
        }
        return _success();
    }

    function _deliver(address from, CrazyBalance amount) internal returns (bool) {
        (CrazyBalance balance, Shares shares, Balance cachedTotalSupply, Shares cachedTotalShares) = _balanceOf(from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        if (amount == balance) {
            cachedTotalShares = cachedTotalShares - shares;
            shares = ZERO_SHARES;
        } else {
            (shares, cachedTotalShares) =
                ReflectMath.getDeliverShares(amount.toBalance(from), cachedTotalSupply, cachedTotalShares, shares);
        }

        _sharesOf[from] = shares;
        _totalShares = cachedTotalShares;
        emit Transfer(from, address(0), amount.toExternal());

        pair.sync();

        return true;
    }

    function deliver(uint256 amount) external returns (bool) {
        if (!_deliver(msg.sender, amount.fromExternal())) {
            return false;
        }
        return _success();
    }

    function burnFrom(address from, uint256 amount) external returns (bool) {
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance(from, amount.fromExternal());
        if (!success) {
            return false;
        }
        if (!_burn(from, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount.fromExternal(), currentTempAllowance, currentAllowance);
        return _success();
    }

    function deliverFrom(address from, uint256 amount) external returns (bool) {
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance(from, amount.fromExternal());
        if (!success) {
            return false;
        }
        if (!_deliver(from, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount.fromExternal(), currentTempAllowance, currentAllowance);
        return _success();
    }

    // TODO: a better solution would be to maintain a list of whales and keeping them under the
    // limit. This doesn't present a DoS vulnerability because the definition of a whale is a
    // proportion of the total shares, thus the maximum number of whales is that proportion
    function punishWhale(address whale) external returns (bool) {
        (_sharesOf[whale], _totalShares) = _loadAccount(whale);
        if (whale != address(pair)) {
            pair.sync();
        }
        return _success();
    }
}
