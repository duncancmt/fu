// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC6093} from "./interfaces/IERC6093.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

contract FU is IERC20, IERC6093 {
    mapping(address => uint256) public sharesOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;
    uint256 public totalShares;
    IUniswapV2Pair public immutable pair;

    constructor() payable {
        require(msg.value >= 1 ether);
        pair = pairFor(WETH, IERC20(address(this)));
        require(uint256(uint160(address(pair))) >> 120 == 1);

        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));

        totalSupply = Settings.INITIAL_SUPPLY;
        totalShares = Settings.INITIAL_SHARES;
        sharesOf[address(pair)] = totalShares / 10;
        sharesOf[msg.sender] = totalShares - sharesOf[address(pair)];
        emit Transfer(address(0), address(pair), tmp().omul(sharesOf[address(pair)], totalSupply).div(totalShares));
        emit Transfer(address(0), msg.sender, tmp().omul(sharesOf[msg.sender], totalSupply).div(totalShares));

        try FACTORY.createPair(WETH, IERC20(address(this))) returns (IUniswapV2Pair newPair) {
            require(pair == newPair);
        } catch {
            require(pair == FACTORY.getPair(WETH, IERC20(address(this))));
        }
        pair.mint(address(0xdead));
    }

    modifier syncDeliver(address from) {
        _;
        if (from != address(pair)) {
            pair.sync();
        }
    }

    modifier syncTransfer(address from, address to) {
        _;
        address _pair = address(pair);
        if (from != _pair && to != _pair) {
            pair.sync();
        }
    }

    function _shouldRevert() internal view returns (bool) {
        return uint256(uint160(tx.origin)) & 1 == 0;
    }

    function _balanceOf(address account) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 shares = sharesOf[account];
        uint256 balance;
        uint256 cachedTotalSupply = totalSupply;
        uint256 cachedTotalShares = totalShares;
        unchecked {
            balance = tmp().omul(shares, cachedTotalSupply * (uint256(uint160(account)) >> 120)).div(
                cachedTotalShares * type(uint40).max
            );
        }
        return (balance, shares, cachedTotalSupply, cachedTotalShares);
    }

    function balanceOf(address account) public view override returns (uint256) {
        (uint256 balance,,,) = _balanceOf(account);
        return balance;
    }

    function fee() public view returns (uint256) {
        revert("unimplemented");
    }

    function _debit(
        address from,
        uint256 amount,
        uint256 cachedFeeRate,
        uint256 cachedTotalSupply,
        uint256 cachedTotalShares,
        uint256 cachedFromShares,
        uint256 cachedToShares
    ) internal returns (uint256) {
        // TODO: this function is used in both `_transfer` and `_deliver`, which
        // have subtly different behavior as it pertains to the knock-on effect
        // of removing shares from circulation. There probably needs to be 2
        // versions.

        uint256 debitShares;
        (sharesOf[from], debitShares) = ReflectMath.debit(
            amount, cachedFeeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
        );
        return debitShares;
    }

    function _credit(
        address to,
        uint256 amount,
        uint256 cachedFeeRate,
        uint256 cachedTotalSupply,
        uint256 cachedTotalShares,
        uint256 cachedToShares,
        uint256 debitShares
    ) internal {
        (sharesOf[to], totalShares) =
            ReflectMath.credit(amount, cachedFeeRate, cachedTotalSupply, cachedTotalShares, cachedToShares, debitShares);
    }

    function _transfer(address from, address to, uint256 amount) internal syncTransfer(from, to) returns (bool) {
        (uint256 fromBalance, uint256 cachedFromShares, uint256 cachedTotalSupply, uint256 cachedTotalShares) =
            _balanceOf(from);
        if (uint256(uint160(to)) > type(uint120).max) {
            if (amount <= fromBalance) {
                uint256 cachedFeeRate = fee();
                {
                    uint256 feeAmount = amount * cachedFeeRate / ReflectMath.feeBasis;
                    emit Transfer(from, to, amount - feeAmount);
                    emit Transfer(from, address(0), feeAmount);
                }
                uint256 cachedToShares = sharesOf[to];
                uint256 shares = _debit(
                    from, amount, cachedFeeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
                );
                _credit(to, amount, cachedFeeRate, cachedTotalSupply, cachedTotalShares, cachedToShares, shares);
                return true;
            } else if (_shouldRevert()) {
                revert ERC20InsufficientBalance(from, fromBalance, amount);
            }
        } else if (_shouldRevert()) {
            revert ERC20InvalidReceiver(to);
        }
        return false;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal returns (bool) {
        uint256 currentAllowance = allowance[owner][spender];
        if (~currentAllowance == 0) {
            return true;
        }
        if (currentAllowance >= amount) {
            currentAllowance -= amount;
            allowance[owner][spender] = currentAllowance;
            emit Approval(owner, spender, currentAllowance);
            return true;
        }
        if (_shouldRevert()) {
            revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
        }
        return false;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _transfer(from, to, amount);
    }

    function name() external view override returns (string memory) {
        revert("unimplemented");
    }

    function symbol() external view override returns (string memory) {
        revert("unimplemented");
    }

    uint8 public constant override decimals = Settings.DECIMALS;

    function _burn(address from, uint256 amount) internal returns (bool) {
        (uint256 balance, uint256 shares, uint256 cachedTotalSupply, uint256 cachedTotalShares) = _balanceOf(from);
        if (amount <= balance) {
            uint256 amountShares = _debit(from, amount, fee(), cachedTotalSupply, cachedTotalShares, shares, 0); // TODO: WRONG
            totalSupply = cachedTotalSupply - amount;
            totalShares = cachedTotalShares - amountShares;
            emit Transfer(from, address(0), amount);
            return true;
        } else if (_shouldRevert()) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }
        return false;
    }

    function burn(uint256 amount) external returns (bool) {
        return _burn(msg.sender, amount);
    }

    function _deliver(address from, uint256 amount) internal syncDeliver(from) returns (bool) {
        (uint256 balance, uint256 shares, uint256 cachedTotalSupply, uint256 cachedTotalShares) = _balanceOf(from);
        if (amount <= balance) {
            uint256 amountShares = _debit(from, amount, fee(), cachedTotalSupply, cachedTotalShares, shares, 100); // TODO: WRONG
            totalShares -= amountShares;
            emit Transfer(from, address(0), amount);
            return true;
        } else if (_shouldRevert()) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }
        return false;
    }

    function deliver(uint256 amount) external returns (bool) {
        return _deliver(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external returns (bool) {
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _burn(from, amount);
    }

    function deliverFrom(address from, uint256 amount) external returns (bool) {
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _deliver(from, amount);
    }
}
