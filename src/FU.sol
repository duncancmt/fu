// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC6093} from "./interfaces/IERC6093.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";

import {UnsafeMath} from "./lib/UnsafeMath.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";
import {Settings} from "./core/Settings.sol";
import {ReflectMath} from "./core/ReflectMath.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

contract FU is IERC20, IERC6093 {
    using UnsafeMath for uint256;

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
        _mintShares(DEAD, Settings.oneTokenInShares());
        _mintShares(address(pair), totalShares / 10);
        _mintShares(msg.sender, totalShares - sharesOf[address(pair)] - sharesOf[DEAD]);

        try FACTORY.createPair(WETH, IERC20(address(this))) returns (IUniswapV2Pair newPair) {
            require(pair == newPair);
        } catch {
            require(pair == FACTORY.getPair(WETH, IERC20(address(this))));
        }
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

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
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
                (uint256 transferShares, uint256 burnShares) = ReflectMath.getTransferShares(
                    amount, cachedFeeRate, cachedTotalSupply, cachedTotalShares, cachedFromShares, cachedToShares
                );
                if (amount == fromBalance) {
                    burnShares += cachedFromShares - transferShares;
                    transferShares = cachedFromShares;
                }
                sharesOf[from] = cachedFromShares - transferShares;
                sharesOf[to] = cachedToShares + transferShares - burnShares;
                totalShares = cachedTotalShares - burnShares;

                {
                    address _pair = address(pair);
                    if (!(from == _pair || to == _pair)) {
                        IUniswapV2Pair(_pair).sync();
                    }
                }

                return _success();
            } else if (_check()) {
                revert ERC20InsufficientBalance(from, fromBalance, amount);
            }
        } else if (_check()) {
            revert ERC20InvalidReceiver(to);
        }
        return false;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return _success();
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
        if (_check()) {
            revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
        }
        return false;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
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
            uint512 p = alloc().omul(amount, shares);
            uint256 amountShares = p.div(balance);
            if (tmp().omul(amountShares, balance) < p) {
                amountShares++;
            }
            sharesOf[from] = shares - amountShares;
            totalSupply = cachedTotalSupply - amount;
            totalShares = cachedTotalShares - amountShares;
            emit Transfer(from, address(0), amount);
            return _success();
        } else if (_check()) {
            revert ERC20InsufficientBalance(from, balance, amount);
        }
        return false;
    }

    function burn(uint256 amount) external returns (bool) {
        return _burn(msg.sender, amount);
    }

    function _deliver(address from, uint256 amount) internal returns (bool) {
        (uint256 balance, uint256 shares, uint256 cachedTotalSupply, uint256 cachedTotalShares) = _balanceOf(from);
        if (amount <= balance) {
            emit Transfer(from, address(0), amount);
            uint256 amountShares;
            if (amount == balance) {
                amountShares = shares;
            } else {
                amountShares = ReflectMath.getDeliverShares(amount, cachedTotalSupply, cachedTotalShares, shares);
            }
            sharesOf[from] = shares - amountShares;
            totalShares = cachedTotalShares - amountShares;

            pair.sync();

            return _success();
        } else if (_check()) {
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

    function lock(uint256 amount) external returns (bool) {
        return transfer(DEAD, amount);
    }

    function lockFrom(address from, uint256 amount) external returns (bool) {
        return transferFrom(from, DEAD, amount);
    }
}
