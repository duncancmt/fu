// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20Big} from "./interfaces/IERC20Big.sol";
import {IERC6093} from "./interfaces/IERC6093.sol";
import {uint512, tmp, alloc} from "./lib/512Math.sol";

contract FU is IERC20Big, IERC6093 {
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

    constructor() {
        // We have to be able to emit the event, even hypothetically in order for it to show up in the ABI
        if (block.coinbase == address(0xdead)) {
            emit Transfer(address(0), msg.sender, type(uint256).max);
            emit Approval(address(0), address(0), 0);
        }
    }

    function totalSupply() external pure override returns (uint256, uint256) {
        return (type(uint152).max, type(uint256).max);
    }

    function _balanceOf(address account) internal view returns (uint512 r) {
        r = alloc();
        revert("unimplemented");
    }

    function balanceOf(address account) external view override returns (uint256, uint256) {
        return _balanceOf(account).into();
    }

    function _transfer(address from, address to, uint512 amount) internal returns (bool) {
        uint512 fromBalance = _balanceOf(msg.sender);

        if (amount <= fromBalance) {
            revert("unimplemented");
            _logTransfer(from, to, amount);
            return true;
        } else if (uint160(tx.origin) & 1 == 0) {
            (uint256 balance_hi, ) = fromBalance.into();
            (uint256 amount_hi, ) = amount.into();
            revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
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
}
