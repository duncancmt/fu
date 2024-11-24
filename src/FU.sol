// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC2612} from "./interfaces/IERC2612.sol";
import {IERC5267} from "./interfaces/IERC5267.sol";
import {IERC6093} from "./interfaces/IERC6093.sol";
import {IERC7674} from "./interfaces/IERC7674.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";
import {TransientStorageLayout} from "./core/TransientStorageLayout.sol";

import {BasisPoints} from "./core/types/BasisPoints.sol";
import {Shares} from "./core/types/Shares.sol";
import {Balance, fromExternal} from "./core/types/Balance.sol";

import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

contract FU is IERC2612, IERC5267, IERC6093, IERC7674, TransientStorageLayout {
    using UnsafeMath for uint256;
    using ChecksumAddress for address;
    using {fromExternal} for uint256;

    // TODO: use a user-defined type to separate shares-denominated values from balance-denominated values
    mapping(address => Shares) internal _sharesOf;
    mapping(address => uint256) public override nonces;
    mapping(address => mapping(address => uint256)) internal _allowance;
    Balance internal _totalSupply;
    Shares internal _totalShares;
    IUniswapV2Pair public immutable pair;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply.toExternal();
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
    mapping(address => mapping(address => uint256)) private _temporaryAllowance;

    constructor(address[] memory initialHolders) payable {
        require(msg.value >= 1 ether);
        require(initialHolders.length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = pairFor(WETH, this);
        require(uint256(uint160(address(pair))) / Settings.ADDRESS_DIVISOR == 1);

        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));

        _totalSupply = Settings.INITIAL_SUPPLY;
        _totalShares = Settings.INITIAL_SHARES;
        _mintShares(DEAD, Settings.oneTokenInShares());
        _mintShares(address(pair), _totalShares.div(Settings.INITIAL_LIQUIDITY_DIVISOR));
        {
            Shares toMint = _totalShares - _sharesOf[DEAD] - _sharesOf[address(pair)];
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
        pair.mint(DEAD);
    }

    function _mintShares(address to, Shares shares) internal {
        Shares oldShares = _sharesOf[to];
        Shares newShares = oldShares + shares;
        _sharesOf[to] = newShares;
        emit Transfer(
            address(0),
            to,
            // TODO: Use BalanceXShares
            tmp().omul(Shares.unwrap(newShares), Balance.unwrap(_totalSupply)).div(Shares.unwrap(_totalShares))
        );
    }

    function _check() internal view returns (bool) {
        return uint256(blockhash(block.number.unsafeDec())) & 1 == 0;
    }

    function _success() internal view returns (bool) {
        if (_check()) {
            assembly ("memory-safe") {
                stop()
            }
        }
        return true;
    }


    function _scaleDown(Shares shares, address account, Balance totalSupply_, Shares totalShares_)
        internal
        pure
        returns (Balance)
    {
        unchecked {
            return Balance.wrap(
                tmp().omul(
                    Shares.unwrap(shares),
                    Balance.unwrap(totalSupply_) * (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR)
                ).div(Shares.unwrap(totalShares_) * Settings.CRAZY_BALANCE_BASIS)
            );
        }
    }

    function _applyWhaleLimit(Shares shares, Shares totalShares_) internal pure returns (Shares, Shares) {
        Shares whaleLimit = totalShares_.div(Settings.ANTI_WHALE_DIVISOR) - Shares.wrap(1);
        if (shares > whaleLimit) {
            totalShares_ = totalShares_ - (shares - whaleLimit);
            shares = whaleLimit;
        }
    }

    function _scaleUp(Balance balance, address account) internal pure returns (Balance) {
        unchecked {
            // Checking for overflow in the multiplication is unnecessary. Checking for division by
            // zero is required.
            return Balance.wrap(Balance.unwrap(balance) * Settings.CRAZY_BALANCE_BASIS / (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR));
        }
    }

    function _loadAccount(address account) internal view returns (Shares, Shares) {
        return _applyWhaleLimit(_sharesOf[account], _totalShares);
    }

    function _balanceOf(address account) internal view returns (Balance, Shares, Balance, Shares) {
        (Shares shares, Shares cachedTotalShares) = _loadAccount(account);
        Balance cachedTotalSupply = _totalSupply;
        Balance balance = _scaleDown(shares, account, cachedTotalSupply, cachedTotalShares);
        return (balance, shares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        (Balance balance,,,) = _balanceOf(account);
        return balance.toExternal();
    }

    function _fee() internal view returns (BasisPoints) {
        // TODO: set fee to zero and prohibit `deliver` when the shares ratio gets to `Settings.MIN_SHARES_RATIO`
        revert("unimplemented");
    }

    function fee() external view returns (uint256) {
        return BasisPoints.unwrap(_fee());
    }

    function _transfer(address from, address to, Balance amount) internal returns (bool) {
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

        (Balance fromBalance, Shares cachedFromShares, Balance cachedTotalSupply, Shares cachedTotalShares) =
            _balanceOf(from);
        Shares cachedToShares = _sharesOf[to];
        address pair_ = address(pair);
        if (to == pair_) {
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

        if (amount > fromBalance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance.toExternal(), amount.toExternal());
            }
            return false;
        }

        BasisPoints feeRate = _fee();
        // TODO: use shares version of getTransferShares when amount == fromBalance
        (Shares newFromShares, Shares newToShares, Shares newTotalShares) = ReflectMath.getTransferShares(
            _scaleUp(amount, from), feeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
        );
        if (amount == fromBalance) {
            // Burn any dust left over if `from` is sending the whole balance
            // TODO: add an overload of getTransferShares that takes a shares argument instead of an amount argument
            // TODO: if we didn't do the above, then the ordering of this modification with the anti-whale check (and attendant modification of `pair_`'s balance) would be wrong
            newTotalShares = newTotalShares - newFromShares;
            newFromShares = Shares.wrap(0);
        }

        if (newToShares >= newTotalShares.div(Settings.ANTI_WHALE_DIVISOR)) {
            if (to != pair_) {
                if (_check()) {
                    // TODO: maybe make this a new error? It's not exactly an invalid recipient, it's an
                    // invalid (too high) transfer amount
                    revert ERC20InvalidReceiver(to);
                }
                return false;
            }

        // === EFFECTS ARE ALLOWED ONLY FROM HERE DOWN ===
            Balance oldPairBalance = _scaleDown(cachedToShares, pair_, cachedTotalSupply, cachedTotalShares);
            (cachedToShares, cachedTotalShares, cachedTotalSupply) =
                ReflectMath.getBurnShares(castUp(scale(amount, BASIS - feeRate)), cachedTotalSupply, cachedTotalShares, cachedToShares);

            emit Transfer(to, address(0), (oldPairBalance - _scaleDown(newToShares, pair_, cachedTotalSupply, newTotalShares)).toExternal());
            _sharesOf[to] = cachedToShares;
            _totalShares = cachedTotalShares;
            _totalSupply = cachedTotalSupply;

            IUniswapV2Pair(pair_).sync();
            // TODO: use shares version of getTransferShares when amount == fromBalance
            (Shares newFromShares, Shares newToShares, Shares newTotalShares) = ReflectMath.getTransferShares(
                _scaleUp(amount, from), feeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
            );
        }

        {
            // Take note of the `to`/`from` mismatch here. We're converting `to`'s balance into
            // units as if it were held by `from`
            Balance transferAmount = _scaleDown(newToShares, from, cachedTotalSupply, newTotalShares)
                - _scaleDown(cachedToShares, from, cachedTotalSupply, cachedTotalShares);
            Balance burnAmount = amount - transferAmount;
            emit Transfer(from, to, transferAmount.toExternal());
            emit Transfer(from, address(0), burnAmount.toExternal());
        }
        _sharesOf[from] = newFromShares;
        _sharesOf[to] = newToShares;
        _totalShares = newTotalShares;

        if (!(from == pair_ || to == pair_)) {
            IUniswapV2Pair(pair_).sync();
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
        _allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return _success();
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        uint256 temporaryAllowance = _getTemporaryAllowance(_temporaryAllowance, owner, spender);
        if (~temporaryAllowance == 0) {
            return temporaryAllowance;
        }
        uint256 allowance_ = _allowance[owner][spender];
        unchecked {
            allowance_ += temporaryAllowance;
            allowance_ = allowance_ < temporaryAllowance ? type(uint256).max : allowance_;
        }
        return allowance_;
    }

    function _checkAllowance(address owner, uint256 amount) internal view returns (bool, uint256, uint256) {
        uint256 currentTempAllowance = _getTemporaryAllowance(_temporaryAllowance, owner, msg.sender);
        if (currentTempAllowance >= amount) {
            return (true, currentTempAllowance, 0);
        }
        uint256 currentAllowance = _allowance[owner][msg.sender];
        unchecked {
            if (currentAllowance >= amount - currentTempAllowance) {
                return (true, currentTempAllowance, currentAllowance);
            }
        }
        if (_check()) {
            revert ERC20InsufficientAllowance(msg.sender, currentAllowance, amount);
        }
        return (false, 0, 0);
    }

    function _spendAllowance(address owner, uint256 amount, uint256 currentTempAllowance, uint256 currentAllowance)
        internal
    {
        if (~currentTempAllowance == 0) {
            // TODO: maybe remove this branch
            return;
        }
        if (currentAllowance == 0) {
            unchecked {
                _setTemporaryAllowance(_temporaryAllowance, owner, msg.sender, currentTempAllowance - amount);
            }
            return;
        }
        if (currentTempAllowance != 0) {
            unchecked {
                amount -= currentTempAllowance;
            }
            _setTemporaryAllowance(_temporaryAllowance, owner, msg.sender, 0);
        }
        if (~currentAllowance == 0) {
            return;
        }
        currentAllowance -= amount;
        _allowance[owner][msg.sender] = currentAllowance;
        emit Approval(owner, msg.sender, currentAllowance);
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        (bool success, uint256 currentTempAllowance, uint256 currentAllowance) = _checkAllowance(from, amount);
        if (!success) {
            return false;
        }
        if (!_transfer(from, to, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount, currentTempAllowance, currentAllowance);
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
        _allowance[owner][spender] = amount;
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

    function temporaryApprove(address spender, uint256 amount) external override returns (bool) {
        _setTemporaryAllowance(_temporaryAllowance, msg.sender, spender, amount);
        return _success();
    }

    function _burn(address from, Balance amount) internal returns (bool) {
        (Balance balance, Shares shares, Balance cachedTotalSupply, Shares cachedTotalShares) = _balanceOf(from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }

        if (amount == balance) {
            cachedTotalShares = cachedTotalShares - shares;
            shares = Shares.wrap(0);
        } else {
            // TODO: Use BalanceXShares
            uint512 p = alloc().omul(Balance.unwrap(amount), Shares.unwrap(shares));
            Shares burnShares = Shares.wrap(p.div(Balance.unwrap(balance)));
            burnShares = burnShares.inc(tmp().omul(Shares.unwrap(burnShares), Balance.unwrap(balance)) < p);
            shares = shares - burnShares;
            cachedTotalShares = cachedTotalShares - burnShares;
        }
        _sharesOf[from] = shares;
        _totalSupply = cachedTotalSupply - _scaleUp(amount, from);
        _totalShares = cachedTotalShares;
        emit Transfer(from, address(0), amount.toExternal());
        return true;
    }

    function burn(uint256 amount) external returns (bool) {
        if (!_burn(msg.sender, amount.fromExternal())) {
            return false;
        }
        return _success();
    }

    function _deliver(address from, Balance amount) internal returns (bool) {
        (Balance balance, Shares shares, Balance cachedTotalSupply, Shares cachedTotalShares) = _balanceOf(from);
        if (amount > balance) {
            if (_check()) {
                revert ERC20InsufficientBalance(from, balance.toExternal(), amount.toExternal());
            }
            return false;
        }
        if (amount == balance) {
            cachedTotalShares = cachedTotalShares - shares;
            shares = Shares.wrap(0);
        } else {
            (shares, cachedTotalShares) =
                ReflectMath.getDeliverShares(_scaleUp(amount, from), cachedTotalSupply, cachedTotalShares, shares);
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
        (bool success, uint256 currentTempAllowance, uint256 currentAllowance) = _checkAllowance(from, amount);
        if (!success) {
            return false;
        }
        if (!_burn(from, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount, currentTempAllowance, currentAllowance);
        return _success();
    }

    function deliverFrom(address from, uint256 amount) external returns (bool) {
        (bool success, uint256 currentTempAllowance, uint256 currentAllowance) = _checkAllowance(from, amount);
        if (!success) {
            return false;
        }
        if (!_deliver(from, amount.fromExternal())) {
            return false;
        }
        _spendAllowance(from, amount, currentTempAllowance, currentAllowance);
        return _success();
    }

    // TODO: a better solution would be to maintain a list of whales and keeping them under the
    // limit. This doesn't present a DoS vulnerability because the definition of a whale is a
    // proportion of the total shares, thus the maximum number of whales is that proportion
    function punishWhale(address whale) external returns (bool) {
        (_sharesOf[whale], _totalShares) = _loadAccount(whale);
        IUniswapV2Pair pair_ = pair;
        if (whale != address(pair_)) {
            pair_.sync();
        }
        return _success();
    }
}
