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

import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {ChecksumAddress} from "./lib/ChecksumAddress.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

contract FU is IERC2612, IERC5267, IERC6093, IERC7674, TransientStorageLayout {
    using UnsafeMath for uint256;
    using ChecksumAddress for address;

    // TODO: use a user-defined type to separate shares-denominated values from balance-denominated values
    mapping(address => uint256) public sharesOf;
    mapping(address => uint256) public override nonces;
    // TODO: use a user-defined type to separate temporary (transient) versus normal allowances
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 public override totalSupply;
    uint256 public totalShares;
    IUniswapV2Pair public immutable pair;

    constructor(address[] memory initialHolders) payable {
        require(msg.value >= 1 ether);
        require(initialHolders.length >= Settings.ANTI_WHALE_DIVISOR * 2);

        pair = pairFor(WETH, IERC20(address(this)));
        require(uint256(uint160(address(pair))) / Settings.ADDRESS_DIVISOR == 1);

        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));

        totalSupply = Settings.INITIAL_SUPPLY;
        totalShares = Settings.INITIAL_SHARES;
        _mintShares(DEAD, Settings.oneTokenInShares());
        _mintShares(address(pair), totalShares / Settings.INITIAL_LIQUIDITY_DIVISOR);
        {
            uint256 toMint = totalShares - sharesOf[DEAD] - sharesOf[address(pair)];
            uint256 toMintEach = toMint / initialHolders.length;
            _mintShares(initialHolders[0], toMint - toMintEach * (initialHolders.length - 1));
            for (uint256 i = 1; i < initialHolders.length; i++) {
                _mintShares(initialHolders[i], toMintEach);
            }
        }

        try FACTORY.createPair(WETH, IERC20(address(this))) returns (IUniswapV2Pair newPair) {
            require(pair == newPair);
        } catch {
            require(pair == FACTORY.getPair(WETH, IERC20(address(this))));
        }
        // TODO: there is a significant risk that `pair` will become a whale. We should add a
        // provision for fixing that
        pair.mint(DEAD);
    }

    function _mintShares(address to, uint256 shares) internal {
        uint256 newShares = (sharesOf[to] += shares);
        emit Transfer(address(0), to, tmp().omul(newShares, totalSupply).div(totalShares));
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

    function _loadAccount(address account) internal view returns (uint256, uint256) {
        uint256 shares = sharesOf[account];
        uint256 cachedTotalShares = totalShares;
        unchecked {
            uint256 whaleLimit = cachedTotalShares / Settings.ANTI_WHALE_DIVISOR - 1;
            if (shares > whaleLimit) {
                cachedTotalShares -= (shares - whaleLimit);
                shares = whaleLimit;
            }
        }
        return (shares, cachedTotalShares);
    }

    function _scaleDown(uint256 shares, address account, uint256 totalSupply_, uint256 totalShares_)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return tmp().omul(shares, totalSupply_ * (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR)).div(
                totalShares_ * Settings.CRAZY_BALANCE_BASIS
            );
        }
    }

    function _scaleUp(uint256 balance, address account) internal pure returns (uint256) {
        unchecked {
            // Checking for overflow in the multiplication is
            // unnecessary. Checking for division by zero is required.
            return balance * Settings.CRAZY_BALANCE_BASIS / (uint256(uint160(account)) / Settings.ADDRESS_DIVISOR);
        }
    }

    function _balanceOf(address account) internal view returns (uint256, uint256, uint256, uint256) {
        (uint256 shares, uint256 cachedTotalShares) = _loadAccount(account);
        uint256 cachedTotalSupply = totalSupply;
        uint256 balance = _scaleDown(shares, account, cachedTotalSupply, cachedTotalShares);
        return (balance, shares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) external view override returns (uint256) {
        (uint256 balance,,,) = _balanceOf(account);
        return balance;
    }

    function fee() public view returns (uint256) {
        // TODO: set fee to zero and prohibit `deliver` when the shares ratio gets to `Settings.MIN_SHARES_RATIO`
        revert("unimplemented");
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        (uint256 fromBalance, uint256 cachedFromShares, uint256 cachedTotalSupply, uint256 cachedTotalShares) =
            _balanceOf(from);
        uint256 cachedToShares = sharesOf[to];
        if (
            // "efficient" addresses can't hold tokens because they have zero multiplier
            uint256(uint160(to)) >= Settings.ADDRESS_DIVISOR
            // anti-whale (also because the reflection math breaks down)
            // we have to check this twice to ensure no underflow in the reflection math
            && cachedToShares < cachedTotalShares / Settings.ANTI_WHALE_DIVISOR
        ) {
            if (amount <= fromBalance) {
                (uint256 newFromShares, uint256 newToShares, uint256 newTotalShares) = ReflectMath.getTransferShares(
                    _scaleUp(amount, from),
                    fee(),
                    cachedTotalSupply,
                    cachedTotalShares,
                    cachedFromShares,
                    cachedToShares
                );
                if (amount == fromBalance) {
                    // Burn any dust left over if `from` is sending the whole balance
                    newTotalShares -= newFromShares;
                    newFromShares = 0;
                }

                if (newToShares < newTotalShares / Settings.ANTI_WHALE_DIVISOR) {
                    // All effects go here
                    unchecked {
                        // Take note of the `to`/`from` mismatch here. We're converting `to`'s
                        // balance into units as if it were held by `from`
                        uint256 transferAmount = _scaleDown(newToShares, from, cachedTotalSupply, newTotalShares)
                            - _scaleDown(cachedToShares, from, cachedTotalSupply, cachedTotalShares);
                        uint256 burnAmount = amount - transferAmount;
                        emit Transfer(from, to, transferAmount);
                        emit Transfer(from, address(0), burnAmount);
                    }
                    sharesOf[from] = newFromShares;
                    sharesOf[to] = newToShares;
                    totalShares = newTotalShares;

                    {
                        address pair_ = address(pair);
                        if (!(from == pair_ || to == pair_)) {
                            IUniswapV2Pair(pair_).sync();
                        }
                    }

                    return true;
                } else if (_check()) {
                    // TODO: maybe make this a new error? It's not exactly an
                    // invalid recipient, it's an invalid (too high) transfer
                    // amount
                    revert ERC20InvalidReceiver(to);
                }
            } else if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance, amount);
            }
        } else if (_check()) {
            // TODO: maybe do a fallback to "normal" transfers if the recipient
            // is the pair?
            revert ERC20InvalidReceiver(to);
        }
        return false;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        if (!_transfer(msg.sender, to, amount)) {
            return false;
        }
        return _success();
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return _success();
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        uint256 temporaryAllowance = _getTemporaryAllowance(owner, spender);
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
        uint256 currentTempAllowance = _getTemporaryAllowance(owner, msg.sender);
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

    function _spendAllowance(address owner, uint256 amount, uint256 currentTempAllowance, uint256 currentAllowance) internal {
        if (~currentTempAllowance == 0) {
            return;
        }
        if (currentAllowance == 0) {
            unchecked {
                _setTemporaryAllowance(owner, msg.sender, currentTempAllowance - amount);
            }
            return;
        }
        if (currentTempAllowance != 0) {
            unchecked {
                amount -= currentTempAllowance;
            }
            _setTemporaryAllowance(owner, msg.sender, 0);
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
        if (!_transfer(from, to, amount)) {
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
        _setTemporaryAllowance(msg.sender, spender, amount);
        return _success();
    }

    function _burn(address from, uint256 amount) internal returns (bool) {
        (uint256 balance, uint256 shares, uint256 cachedTotalSupply, uint256 cachedTotalShares) = _balanceOf(from);
        if (amount <= balance) {
            if (amount == balance) {
                cachedTotalShares -= shares;
                shares = 0;
            } else {
                uint512 p = alloc().omul(amount, shares);
                uint256 burnShares = p.div(balance);
                if (tmp().omul(burnShares, balance) < p) {
                    burnShares++;
                }
                shares -= burnShares;
                cachedTotalShares -= burnShares;
            }
            sharesOf[from] = shares;
            totalSupply = cachedTotalSupply - _scaleUp(amount, from);
            totalShares = cachedTotalShares;
            emit Transfer(from, address(0), amount);
            return true;
        } else if (_check()) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }
        return false;
    }

    function burn(uint256 amount) external returns (bool) {
        if (!_burn(msg.sender, amount)) {
            return false;
        }
        return _success();
    }

    function _deliver(address from, uint256 amount) internal returns (bool) {
        (uint256 balance, uint256 shares, uint256 cachedTotalSupply, uint256 cachedTotalShares) = _balanceOf(from);
        if (amount <= balance) {
            if (amount == balance) {
                cachedTotalShares -= shares;
                shares = 0;
            } else {
                (shares, cachedTotalShares) =
                    ReflectMath.getDeliverShares(_scaleUp(amount, from), cachedTotalSupply, cachedTotalShares, shares);
            }
            sharesOf[from] = shares;
            totalShares = cachedTotalShares;
            emit Transfer(from, address(0), amount);

            pair.sync();

            return true;
        } else if (_check()) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }
        return false;
    }

    function deliver(uint256 amount) external returns (bool) {
        if (!_deliver(msg.sender, amount)) {
            return false;
        }
        return _success();
    }

    function burnFrom(address from, uint256 amount) external returns (bool) {
        (bool success, uint256 currentTempAllowance, uint256 currentAllowance) = _checkAllowance(from, amount);
        if (!success) {
            return false;
        }
        if (!_burn(from, amount)) {
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
        if (!_deliver(from, amount)) {
            return false;
        }
        _spendAllowance(from, amount, currentTempAllowance, currentAllowance);
        return _success();
    }

    function punishWhale(address whale) external returns (bool) {
        (sharesOf[whale], totalShares) = _loadAccount(whale);
        IUniswapV2Pair pair_ = pair;
        if (whale != address(pair_)) {
            pair_.sync();
        }
        return _success();
    }
}
