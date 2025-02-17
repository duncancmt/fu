// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFU} from "../interfaces/IFU.sol";
import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC2612} from "../interfaces/IERC2612.sol";

import {FUStorage} from "../FUStorage.sol";
import {AbstractContext} from "../utils/Context.sol";

import {CrazyBalance, toCrazyBalance} from "../types/CrazyBalance.sol";

abstract contract ERC20Base is IFU, FUStorage, AbstractContext {
    using {toCrazyBalance} for uint256;

    constructor() {
        require(_DOMAIN_TYPEHASH == keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"));
        require(_NAME_HASH == keccak256(bytes(name)));
        require(
            _PERMIT_TYPEHASH
                == keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
        );
        require(_DELEGATION_TYPEHASH == keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"));

        require(block.chainid == _CHAIN_ID);
        _cachedDomainSeparator = _computeDomainSeparator();
    }

    function _success() internal view virtual returns (bool);

    function _transfer(Storage storage $, address from, address to, CrazyBalance amount)
        internal
        virtual
        returns (bool);
    function _burn(Storage storage $, address from, CrazyBalance amount) internal virtual returns (bool);
    function _deliver(Storage storage $, address from, CrazyBalance amount) internal virtual returns (bool);
    function _delegate(Storage storage $, address delegator, address delegatee) internal virtual;

    function _approve(Storage storage $, address owner, address spender, CrazyBalance amount)
        internal
        virtual
        returns (bool);
    function _checkAllowance(Storage storage $, address owner, address spender, CrazyBalance amount)
        internal
        view
        virtual
        returns (bool, CrazyBalance, CrazyBalance);
    function _spendAllowance(
        Storage storage $,
        address owner,
        address spender,
        CrazyBalance amount,
        CrazyBalance currentTempAllowance,
        CrazyBalance currentAllowance
    ) internal virtual returns (bool);

    function _consumeNonce(Storage storage $, address account) internal virtual returns (uint256);
    function clock() public view virtual override returns (uint48);

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) external override returns (bool) {
        return _transfer(_$(), _msgSender(), to, amount.toCrazyBalance()) && _success();
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) external override returns (bool) {
        return _approve(_$(), _msgSender(), spender, amount.toCrazyBalance()) && _success();
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        Storage storage $ = _$();
        address operator = _msgSender();
        CrazyBalance amount_ = amount.toCrazyBalance();
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance($, from, operator, amount_);
        return success && _transfer($, from, to, amount_)
            && _spendAllowance($, from, operator, amount_, currentTempAllowance, currentAllowance) && _success();
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

    bytes32 private constant _DOMAIN_TYPEHASH = 0x8cad95687ba82c2ce50e74f7b754645e5117c3a5bec8151c0726d5857980a866;
    // slither-disable-next-line naming-convention
    bytes32 private constant _NAME_HASH = 0xb614ddaf8c6c224524c95dbfcb82a82be086ec3a639808bbda893d5b4ac93694;
    uint256 private constant _CHAIN_ID = 1;
    bytes32 private immutable _cachedDomainSeparator;

    function _computeDomainSeparator() private view returns (bytes32 r) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x00, _DOMAIN_TYPEHASH)
            mstore(0x20, _NAME_HASH)
            mstore(0x40, chainid())
            mstore(0x60, address())
            r := keccak256(0x00, 0x80)
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
    }

    // slither-disable-next-line naming-convention
    /// @inheritdoc IERC2612
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return block.chainid == _CHAIN_ID ? _cachedDomainSeparator : _computeDomainSeparator();
    }

    bytes32 private constant _PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    uint256 private constant _ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// @inheritdoc IERC2612
    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        // slither-disable-next-line timestamp
        if (~deadline != 0 && block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        Storage storage $ = _$();

        uint256 nonce = _consumeNonce($, owner);
        bytes32 sep = DOMAIN_SEPARATOR();
        address signer;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, _PERMIT_TYPEHASH)
            mstore(add(0x20, ptr), and(_ADDRESS_MASK, owner))
            mstore(add(0x40, ptr), and(_ADDRESS_MASK, spender))
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
            pop(staticcall(gas(), 0x01, 0x00, 0x80, 0x00, 0x20))
            signer := mul(mload(0x00), eq(returndatasize(), 0x20))
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }
        require(_approve($, owner, spender, amount.toCrazyBalance()));
    }

    bytes32 private constant _DELEGATION_TYPEHASH = 0xe48329057bfd03d55e49b547132e39cffd9c1820ad7b9d4c5307691425d15adf;

    function delegate(address delegatee) external override {
        return _delegate(_$(), _msgSender(), delegatee);
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        // slither-disable-next-line timestamp
        if (~expiry != 0 && block.timestamp > expiry) {
            revert ERC5805ExpiredSignature(expiry);
        }
        bytes32 sep = DOMAIN_SEPARATOR();
        address signer;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x00, _DELEGATION_TYPEHASH)
            mstore(0x20, and(_ADDRESS_MASK, delegatee))
            mstore(0x40, nonce)
            mstore(0x60, expiry)
            mstore(0x40, keccak256(0x00, 0x80))
            mstore(0x00, 0x1901)
            mstore(0x20, sep)
            mstore(0x00, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 0x01, 0x00, 0x80, 0x00, 0x20))
            signer := mul(mload(0x00), eq(returndatasize(), 0x20))
            mstore(0x40, ptr)
            mstore(0x60, 0x00)
        }
        if (signer == address(0)) {
            revert ERC5805InvalidSignature();
        }

        Storage storage $ = _$();

        uint256 expectedNonce = _consumeNonce($, signer);
        if (nonce != expectedNonce) {
            revert ERC5805InvalidNonce(nonce, expectedNonce);
        }
        return _delegate($, signer, delegatee);
    }

    /// @inheritdoc IFU
    function burn(uint256 amount) external override returns (bool) {
        return _burn(_$(), _msgSender(), amount.toCrazyBalance()) && _success();
    }

    /// @inheritdoc IFU
    function deliver(uint256 amount) external override returns (bool) {
        return _deliver(_$(), _msgSender(), amount.toCrazyBalance()) && _success();
    }

    /// @inheritdoc IFU
    function burnFrom(address from, uint256 amount) external override returns (bool) {
        Storage storage $ = _$();
        address operator = _msgSender();
        CrazyBalance amount_ = amount.toCrazyBalance();
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance($, from, operator, amount_);
        return success && _burn($, from, amount_)
            && _spendAllowance($, from, operator, amount_, currentTempAllowance, currentAllowance) && _success();
    }

    /// @inheritdoc IFU
    function deliverFrom(address from, uint256 amount) external override returns (bool) {
        Storage storage $ = _$();
        address operator = _msgSender();
        CrazyBalance amount_ = amount.toCrazyBalance();
        (bool success, CrazyBalance currentTempAllowance, CrazyBalance currentAllowance) =
            _checkAllowance($, from, operator, amount_);
        return success && _deliver($, from, amount_)
            && _spendAllowance($, from, operator, amount_, currentTempAllowance, currentAllowance) && _success();
    }
}
