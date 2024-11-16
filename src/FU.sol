// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20Big} from "./interfaces/IERC20Big.sol";
import {IERC6093} from "./interfaces/IERC6093.sol";

import {uint512, tmp, alloc, uint512_external} from "./lib/512Math.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {FACTORY} from "./interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";

IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

contract FU is IERC20Big, IERC6093 {
    mapping(address => uint512_external) _sharesOf;
    uint512_external internal _totalSupply;
    uint512_external internal _totalShares;
    IUniswapV2Pair public immutable pair;

    function _logTransfer(address from, address to, uint512 value) internal {
        bytes32 selector = IERC20Big.Transfer.selector;
        assembly ("memory-safe") {
            log3(value, 0x40, selector, and(0xffffffffffffffffffffffffffffffffffffffff, from), and(0xffffffffffffffffffffffffffffffffffffffff, to))
        }
    }

    function _logApproval(address owner, address spender, uint512 value) internal {
        bytes32 selector = IERC20Big.Approval.selector;
        assembly ("memory-safe") {
            log3(value, 0x40, selector, and(0xffffffffffffffffffffffffffffffffffffffff, owner), and(0xffffffffffffffffffffffffffffffffffffffff, spender))
        }
    }

    constructor() payable {
        assert(msg.value == 1 ether);
        pair = FACTORY.createPair(WETH, IERC20(address(this)));
        assert(uint160(address(pair)) >> 120 == 1);

        (bool success, ) = address(WETH).call{value: msg.value}("");
        assert(success);
        assert(WETH.transfer(address(pair), msg.value));
        assert(WETH.balanceOf(address(pair)) == msg.value);

        uint512 initialSupply = alloc().from(type(uint152).max, type(uint256).max);
        _totalSupply = initialSupply.toExternal();

        uint512 initialShares = alloc().from(type(uint256).max, type(uint256).max); // TODO: correctly initialize `_totalShares`
        uint512 sharesToLiquidity = alloc().odiv(initialShares, 10);
        _mintShares(address(pair), sharesToLiquidity);
        _mintShares(msg.sender, tmp().osub(initialShares, sharesToLiquidity));

        pair.mint(msg.sender);

        // We have to be able to emit the event, even hypothetically, in order
        // for it to show up in the ABI
        if (block.coinbase == address(this)) {
            emit Transfer(address(0), address(0), 0);
            emit Approval(address(0), address(0), 0);
        }
    }

    modifier sync() {
        _;
        pair.sync();
    }

    function _mintShares(address to, uint512 shares) internal {
        revert("unimplemented");
    }

    function totalSupply() external view override returns (uint256, uint256) {
        return _totalSupply.into().into();
    }

    function _balanceOf(address account) internal view returns (uint512 r) {
        r = alloc();
        revert("unimplemented");
    }

    function balanceOf(address account) external view override returns (uint256, uint256) {
        return _balanceOf(account).into();
    }

    function _transfer(address from, address to, uint512 amount) internal sync returns (bool) {
        uint512 fromBalance = _balanceOf(msg.sender);
        if (to > address(0xffff)) {
            if (amount <= fromBalance) {
                revert("unimplemented");
                _logTransfer(from, to, amount);
                return true;
            } else if (uint160(tx.origin) & 1 == 0) {
                (uint256 balance_hi, ) = fromBalance.into();
                (uint256 amount_hi, ) = amount.into();
                revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
            }
        } else if (uint160(tx.origin) & 1 == 0) {
            revert ERC20InvalidReceiver(to);
        }
        return false;
    }

    function transfer(address to, uint256 amount_hi) external override returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x44)
            }
            amount.from(amount_hi, amount_lo);
        }
        return _transfer(msg.sender, to, amount);
    }

    function _allowance(address owner, address spender) internal view returns (uint512 r) {
        r = alloc();
        revert("unimplemented");
    }

    function allowance(address owner, address spender) external view override returns (uint256, uint256) {
        return _allowance(owner, spender).into();
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        revert("unimplemented");
    }

    function _spendAllowance(address owner, address spender, uint512 amount) internal returns (bool) {
        revert("unimplemented");
    }

    function transferFrom(address from, address to, uint256 amount_hi) external override returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x64)
            }
            amount.from(amount_hi, amount_lo);
        }
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

    uint8 public constant override decimals = 40;

    function _burn(address from, uint512 amount) internal returns (bool) {
        uint512 fromBalance = _balanceOf(msg.sender);
        if (amount <= fromBalance) {
            revert("unimplemented");
            _logTransfer(from, address(0), amount);
            return true;
        } else if (uint160(tx.origin) & 1 == 0) {
            (uint256 balance_hi, ) = fromBalance.into();
            (uint256 amount_hi, ) = amount.into();
            revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
        }
        return false;
    }

    function burn(uint256 amount_hi) external returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x24)
            }
            amount.from(amount_hi, amount_lo);
        }
        return _burn(msg.sender, amount);
    }

    function _deliver(address from, uint512 amount) internal sync returns (bool) {
        uint512 fromBalance = _balanceOf(msg.sender);
        if (amount <= fromBalance) {
            revert("unimplemented");
            _logTransfer(from, address(0), amount);
            return true;
        } else if (uint160(tx.origin) & 1 == 0) {
            (uint256 balance_hi, ) = fromBalance.into();
            (uint256 amount_hi, ) = amount.into();
            revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
        }
        return false;
    }

    function deliver(uint256 amount_hi) external returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x24)
            }
            amount.from(amount_hi, amount_lo);
        }
        return _deliver(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount_hi) external returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x44)
            }
            amount.from(amount_hi, amount_lo);
        }
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _burn(from, amount);
    }

    function deliverFrom(address from, uint256 amount_hi) external returns (bool) {
        uint512 amount = alloc();
        {
            uint256 amount_lo;
            assembly ("memory-safe") {
                amount_lo := calldataload(0x44)
            }
            amount.from(amount_hi, amount_lo);
        }
        if (!_spendAllowance(from, msg.sender, amount)) {
            return false;
        }
        return _deliver(from, amount);
    }
}
