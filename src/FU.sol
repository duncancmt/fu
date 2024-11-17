// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC6093} from "./interfaces/IERC6093.sol";

import {uint512, tmp, alloc, uint512_external} from "./lib/512Math.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY, pairFor} from "./interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";

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

        totalSupply = type(uint152).max;
        totalShares = type(uint256).max;
        sharesOf[address(pair)] = type(uint256).max / 10;
        emit Transfer(address(0), address(pair), type(uint152).max / 10);
        sharesOf[msg.sender] = type(uint256).max - type(uint256).max / 10;
        emit Transfer(address(0), msg.sender, type(uint152).max - type(uint152).max / 10);

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

    function _burnTokens(uint512 amount) internal {
        revert("unimplemented");
    }

    function balanceOf(address account) public view override returns (uint256) {
        unchecked {
            return
                tmp().omul(sharesOf[account], totalSupply * (uint256(uint160(account)) >> 120)).div(totalShares * type(uint40).max);
        }
    }

    function _debit(address from, uint512 amount) internal {
        // TODO: this function is used in both `_transfer` and `_deliver`, which
        // have subtly different behavior as it pertains to the knock-on effect
        // of removing shares from circulation. There probably needs to be 2
        // versions.
        revert("unimplemented");
    }

    function _credit(address to, uint512 amount) internal {
        revert("unimplemented");
    }

    function _transfer(address from, address to, uint512 amount) internal syncTransfer(from, to) returns (bool) {
        uint512 fromBalance = balanceOf(msg.sender);
        if (uint256(uint160(to)) > type(uint120).max) {
            if (amount <= fromBalance) {
                _debit(from, amount);
                _credit(to, amount);
                emit Transfer(from, to, amount);
                // TODO: log fee amount
                return true;
            } else if (_shouldRevert()) {
                (uint256 balance_hi,) = fromBalance.into();
                (uint256 amount_hi,) = amount.into();
                revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
            }
        } else if (_shouldRevert()) {
            revert ERC20InvalidReceiver(to);
        }
        return false;
    }

    function _amount(uint256 amount_hi, uint256 normalCalldataSize) internal pure returns (uint512) {
        uint512 amount = alloc();
        uint256 amount_lo;
        assembly ("memory-safe") {
            amount_lo := calldataload(normalCalldataSize)
        }
        return amount.from(amount_hi, amount_lo);
    }

    function transfer(address to, uint256 amount_hi) external override returns (bool) {
        return _transfer(msg.sender, to, _amount(amount_hi, 0x44));
    }

    function approve(address spender, uint256 amount_hi) external returns (bool) {
        uint512 amount;
        if (amount_hi == type(uint256).max) {
            amount = alloc().from(amount_hi, amount_hi);
        } else {
            amount = _amount(amount_hi, 0x44);
        }
        allowance[msg.sender][spender] = amount.toExternal();
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint512 amount) internal returns (bool) {
        uint512 currentAllowance = allowance[owner][spender].into();
        if (currentAllowance.isMax()) {
            return true;
        }
        if (currentAllowance >= amount) {
            currentAllowance.isub(amount);
            allowance[owner][spender] = currentAllowance.toExternal();
            emit Approval(owner, spender, currentAllowance);
            return true;
        }
        if (_shouldRevert()) {
            (uint256 currentAllowance_hi,) = currentAllowance.into();
            (uint256 amount_hi,) = amount.into();
            revert ERC20InsufficientAllowance(spender, currentAllowance_hi, amount_hi);
        }
        return false;
    }

    function transferFrom(address from, address to, uint256 amount_hi) external override returns (bool) {
        uint512 amount = _amount(amount_hi, 0x64);
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

    uint8 public constant override decimals = 36;

    function _burn(address from, uint512 amount) internal returns (bool) {
        uint512 fromBalance = balanceOf(msg.sender);
        if (amount <= fromBalance) {
            _debit(from, amount);
            _burnTokens(amount);
            emit Transfer(from, address(0), amount);
            return true;
        } else if (_shouldRevert()) {
            (uint256 balance_hi,) = fromBalance.into();
            (uint256 amount_hi,) = amount.into();
            revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
        }
        return false;
    }

    function burn(uint256 amount_hi) external returns (bool) {
        return _burn(msg.sender, _amount(amount_hi, 0x24));
    }

    function _deliver(address from, uint512 amount) internal syncDeliver(from) returns (bool) {
        uint512 fromBalance = balanceOf(msg.sender);
        if (amount <= fromBalance) {
            _debit(from, amount);
            emit Transfer(from, address(0), amount);
            return true;
        } else if (_shouldRevert()) {
            (uint256 balance_hi,) = fromBalance.into();
            (uint256 amount_hi,) = amount.into();
            revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
        }
        return false;
    }

    function deliver(uint256 amount_hi) external returns (bool) {
        return _deliver(msg.sender, _amount(amount_hi, 0x24));
    }

    function burnFrom(address from, uint256 amount_hi) external returns (bool) {
        uint512 amount = _amount(amount_hi, 0x44);
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _burn(from, amount);
    }

    function deliverFrom(address from, uint256 amount_hi) external returns (bool) {
        uint512 amount = _amount(amount_hi, 0x44);
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _deliver(from, amount);
    }
}
