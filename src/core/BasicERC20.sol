// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC2612} from "../interfaces/IERC2612.sol";
import {IERC5267} from "../interfaces/IERC5267.sol";
import {IERC5805} from "../interfaces/IERC5805.sol";
import {IERC6093} from "../interfaces/IERC6093.sol";
import {IERC7674} from "../interfaces/IERC7674.sol";

import {CrazyBalance, toCrazyBalance} from "./CrazyBalance.sol";

abstract contract BasicERC20 is IERC2612, IERC5267, IERC5805, IERC6093, IERC7674 {
    using {toCrazyBalance} for uint256;

    constructor() {
        require(_DOMAIN_TYPEHASH == keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
        require(_NAME_HASH() == keccak256(bytes(name())));
        require(
            _PERMIT_TYPEHASH
                == keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
        );
        require(_DELEGATION_TYPEHASH == keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"));
    }

    function _success() internal view virtual returns (bool);

    function _transfer(address from, address to, CrazyBalance amount) internal virtual returns (bool);
    function _burn(address from, CrazyBalance amount) internal virtual returns (bool);
    function _deliver(address from, CrazyBalance amount) internal virtual returns (bool);
    function _delegate(address delegator, address delegatee) internal virtual;

    function name() public pure virtual returns (string memory);
    function _NAME_HASH() internal pure virtual returns (bytes32);
    function _consumeNonce(address account) internal virtual returns (uint256);
    function clock() public view virtual override returns (uint48);

    function _approve(address owner, address spender, CrazyBalance amount) internal virtual returns (bool);
    function _checkAllowance(address owner, CrazyBalance amount)
        internal
        view
        virtual
        returns (bool, CrazyBalance, CrazyBalance);
    function _spendAllowance(
        address owner,
        CrazyBalance amount,
        CrazyBalance currentTempAllowance,
        CrazyBalance currentAllowance
    ) internal virtual;

    function approve(address spender, uint256 amount) external override returns (bool) {
        if (!_approve(msg.sender, spender, amount.toCrazyBalance())) {
            return false;
        }
        return _success();
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
        name_ = name();
        chainId = block.chainid;
        verifyingContract = address(this);
    }

    bytes32 private constant _DOMAIN_TYPEHASH = 0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866;

    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() public view override returns (bytes32 r) {
        bytes32 _NAME_HASH_ = _NAME_HASH();
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x00, _DOMAIN_TYPEHASH)
            mstore(0x20, _NAME_HASH_)
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
        uint256 nonce = _consumeNonce(owner);
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
        require(_approve(owner, spender, amount.toCrazyBalance()));
    }

    bytes32 private constant _DELEGATION_TYPEHASH = 0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf;

    function delegate(address delegatee) external override {
        return _delegate(msg.sender, delegatee);
    }
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
        uint256 expectedNonce = _consumeNonce(signer);
        if (nonce != expectedNonce) {
            revert ERC5805InvalidNonce(nonce, expectedNonce);
        }
        return _delegate(signer, delegatee);
    }

    function burn(uint256 amount) external returns (bool) {
        if (!_burn(msg.sender, amount.toCrazyBalance())) {
            return false;
        }
        return _success();
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
}
