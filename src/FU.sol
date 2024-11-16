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
    mapping(address => mapping(address => uint512_external)) public override allowance;
    uint512_external internal _totalSupply;
    uint512_external internal _totalShares;
    IUniswapV2Pair public immutable pair;

    function _logBig(bytes32 selector, address a, address b, uint512 amount) internal {
        assembly ("memory-safe") {
            log3(
                amount,
                0x40,
                selector,
                and(0xffffffffffffffffffffffffffffffffffffffff, a),
                and(0xffffffffffffffffffffffffffffffffffffffff, b)
            )
        }
    }

    function _logTransfer(address from, address to, uint512 amount) internal {
        _logBig(IERC20Big.Transfer.selector, from, to, amount);
    }

    function _logApproval(address owner, address spender, uint512 amount) internal {
        _logBig(IERC20Big.Approval.selector, owner, spender, amount);
    }

    constructor() payable {
        require(msg.value == 1 ether);
        try FACTORY.createPair(WETH, IERC20(address(this))) returns (IUniswapV2Pair newPair) {
            pair = newPair;
        } catch {
            pair = FACTORY.getPair(WETH, IERC20(address(this)));
        }
        require(uint160(address(pair)) >> 120 == 1);

        (bool success,) = address(WETH).call{value: msg.value}("");
        require(success);
        require(WETH.transfer(address(pair), msg.value));

        uint512 initialSupply = alloc().from(type(uint152).max, type(uint256).max);
        _totalSupply = initialSupply.toExternal();

        uint512 initialShares = alloc().from(type(uint256).max, type(uint256).max); // TODO: correctly initialize `_totalShares`
        _totalShares = initialShares.toExternal();
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

    function _mintShares(address to, uint512 shares) internal {
        revert("unimplemented");
    }

    function _burnTokens(uint512 amount) internal {
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
        uint512 fromBalance = _balanceOf(msg.sender);
        if (to > address(0xffff)) {
            if (amount <= fromBalance) {
                _debit(from, amount);
                _credit(to, amount);
                _logTransfer(from, to, amount);
                // TODO: log fee amount
                return true;
            } else if (uint160(tx.origin) & 1 == 0) {
                (uint256 balance_hi,) = fromBalance.into();
                (uint256 amount_hi,) = amount.into();
                revert ERC20InsufficientBalance(msg.sender, balance_hi, amount_hi);
            }
        } else if (uint160(tx.origin) & 1 == 0) {
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
        _logApproval(msg.sender, spender, amount);
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
            _logApproval(owner, spender, currentAllowance);
            return true;
        }
        if (uint160(tx.origin) & 1 == 0) {
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

    uint8 public constant override decimals = 40;

    function _burn(address from, uint512 amount) internal returns (bool) {
        uint512 fromBalance = _balanceOf(msg.sender);
        if (amount <= fromBalance) {
            _debit(from, amount);
            _burnTokens(amount);
            _logTransfer(from, address(0), amount);
            return true;
        } else if (uint160(tx.origin) & 1 == 0) {
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
        uint512 fromBalance = _balanceOf(msg.sender);
        if (amount <= fromBalance) {
            _debit(from, amount);
            _logTransfer(from, address(0), amount);
            return true;
        } else if (uint160(tx.origin) & 1 == 0) {
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
