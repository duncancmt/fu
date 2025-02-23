// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IFU} from "src/interfaces/IFU.sol";
import {FU} from "src/FU.sol";
import {Settings} from "src/core/Settings.sol";
import {Buyback} from "src/Buyback.sol";

import {QuickSort} from "script/QuickSort.sol";
import {Hexlify} from "script/Hexlify.sol";
import {ChecksumAddress} from "src/lib/ChecksumAddress.sol";

import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory, FACTORY, pairFor} from "src/interfaces/IUniswapV2Factory.sol";

import {Vm, VmSafe} from "@forge-std/Vm.sol";
import {StdAssertions} from "@forge-std/StdAssertions.sol";

import "./EnvironmentConstants.sol";

import {console} from "@forge-std/console.sol";

abstract contract Common is StdAssertions {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    bytes32 internal constant BASE_SLOT = 0x00000000000000000000000000000000e086ec3a639808bbda893d5b4ac93600;

    IFU internal fu;
    Buyback internal buyback;
    address internal pair;
    address[] internal actors;
    mapping(address => bool) internal isActor;

    function setUpActors(address[] memory initialActors) internal {
        for (uint256 i; i < initialActors.length; i++) {
            address actor = initialActors[i];
            actors.push(actor);
            isActor[actor] = true;
        }
    }

    function getActor(uint256 actorIndex) internal virtual returns (address actor) {
        actor = actors[actorIndex % actors.length];
        console.log("actor", actor);
    }

    function getActor(address seed) internal returns (address) {
        return getActor(uint160(seed));
    }

    function maybeCreateActor(address newActor) internal virtual {
        if (newActor == address(0)) {
            return;
        }
        if (newActor == DEAD) {
            return;
        }
        if (newActor == address(fu)) {
            return;
        }
        if (isActor[newActor]) {
            return;
        }

        isActor[newActor] = true;
        actors.push(newActor);
        assertEq(fu.balanceOf(newActor), 0);
        assertEq(fu.delegates(newActor), address(0));
    }

    function saveActor(address actor) internal virtual {
        assertNotEq(actor, address(0));
        assertNotEq(actor, DEAD);
        assertNotEq(actor, address(fu));
        assertTrue(isActor[actor]);
    }

    function callOptionalReturn(bytes memory data) internal returns (bool success, bytes memory returndata) {
        (success, returndata) = address(fu).call(data);
        success = success && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    function assertNoMutation(VmSafe.AccountAccess[] memory accountAccesses, VmSafe.Log[] memory logs) internal pure {
        assertEq(logs.length, 0, "emitted event on failure");
        for (uint256 i; i < accountAccesses.length; i++) {
            VmSafe.AccountAccess memory accountAccess = accountAccesses[i];
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.CallCode), "CALLCODE");
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.Create), "CREATE");
            assertNotEq(uint8(accountAccess.kind), uint8(VmSafe.AccountAccessKind.SelfDestruct), "SELFDESTRUCT");
            assertEq(accountAccess.oldBalance, accountAccess.newBalance, "modified balance");
            assertEq(accountAccess.value, 0, "sent ETH");
            VmSafe.StorageAccess[] memory storageAccesses = accountAccess.storageAccesses;
            for (uint256 j; j < storageAccesses.length; j++) {
                VmSafe.StorageAccess memory storageAccess = storageAccesses[j];
                assertFalse(storageAccess.isWrite, "wrote storage");
            }
        }
    }

    function assume(bool condition) internal pure virtual {
        vm.assume(condition);
    }

    function label(address target, string memory name) internal virtual {
        vm.label(target, name);
    }

    function prank(address sender) internal virtual {
        vm.prank(sender);
    }

    function setNonce(address who, uint64 newNonce) internal virtual {
        vm.setNonce(who, newNonce);
    }

    function deal(address who, uint256 value) internal virtual {
        vm.deal(who, value);
    }

    function setBaseFee(uint256 newBaseFee) internal {
        vm.fee(newBaseFee);
    }

    function setChainId(uint256 newChainId) internal {
        vm.chainId(newChainId);
    }

    function warp(uint256 newTimestamp) internal {
        vm.warp(newTimestamp);
    }

    function getBlockTimestamp() internal view returns (uint256) {
        return vm.getBlockTimestamp();
    }

    function load(address account, bytes32 slot) internal view returns (bytes32) {
        return vm.load(account, slot);
    }

    function store(address account, bytes32 slot, bytes32 newValue) internal {
        return vm.store(account, slot, newValue);
    }

    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) internal {
        vm.expectEmit(topic1, topic2, topic3, data, emitter);
    }

    function expectRevert(bytes memory reason) internal {
        vm.expectRevert(reason);
    }
}

contract FUDeploy is Common {
    using QuickSort for address[];
    using Hexlify for bytes32;

    IUniswapV2Factory internal constant UNIV2_FACTORY = IUniswapV2Factory(univ2Factory);
    IERC20 internal constant WETH = IERC20(weth);
    uint256 internal constant EPOCH = 1740721485;
    uint256 internal deployTime;

    function deployFuDependenciesFoundry() internal {
        // Deploy WETH
        bytes memory initcode = wethInit;
        setNonce(wethDeployer, wethDeployerNonce);
        prank(wethDeployer);
        assembly ("memory-safe") {
            if xor(weth, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(weth, "WETH");

        // Deploy the UniswapV2 factory
        initcode = univ2FactoryInit;
        setNonce(univ2FactoryDeployer, univ2FactoryDeployerNonce);
        prank(univ2FactoryDeployer);
        assembly ("memory-safe") {
            if xor(univ2Factory, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(univ2Factory, "Uniswap V2 Factory");

        // Optionally deploy the deployment proxy, if it doesn't exist
        if (deterministicDeployerFactory.codehash != 0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989)
        {
            initcode = deterministicDeployerFactoryInit;
            setNonce(deterministicDeployerFactoryDeployer, deterministicDeployerFactoryDeployerNonce);
            prank(deterministicDeployerFactoryDeployer);
            assembly ("memory-safe") {
                if xor(deterministicDeployerFactory, create(0x00, add(0x20, initcode), mload(initcode))) {
                    revert(0x00, 0x00)
                }
            }
            label(deterministicDeployerFactory, "Create2Deployer");
        }
    }

    /*
    function deployFuDependenciesMedusa() internal {
        // Deploy WETH
        vm.etch(weth, wethRuntime);
        label(weth, "WETH");

        // Deploy the UniswapV2 factory
        vm.etch(univ2Factory, univ2FactoryRuntime);
        vm.store(univ2Factory, bytes32(uint256(1)), bytes32(uint256(uint160(univ2FactoryFeeToSetter))));
        label(univ2Factory, "Uniswap V2 Factory");

        // Deploy the deterministic deployer factory
        vm.etch(deterministicDeployerFactory, deterministicDeployerFactoryRuntime);
        label(deterministicDeployerFactory, "Create2Deployer");
    }
    */

    function deployFuDependencies() internal virtual {
        return deployFuDependenciesFoundry();
    }

    function deployFu() internal returns (IFU fu_, Buyback buyback_, address[] memory initialHolders) {
        initialHolders = new address[](Settings.ANTI_WHALE_DIVISOR * 2);
        for (uint256 i; i < initialHolders.length; i++) {
            // Generate unique addresses
            address holder;
            assembly ("memory-safe") {
                mstore(0x00, add("FU holder", i))
                holder := keccak256(0x00, 0x20)
            }
            initialHolders[i] = holder;
        }
        initialHolders.quickSort();

        setChainId(1);

        deployFuDependencies();

        bytes32 fuSalt = 0x0000000000000000000000000000000000000000000000000000000160b54f9c;
        bytes32 buybackSalt = 0x00000000000000000000000000000000000000000000000000000001d615672b;
        bytes memory fuInitcode = bytes.concat(
            type(FU).creationCode,
            abi.encode(bytes20(keccak256("git commit")), string("I am totally an SVG image, I promise"), initialHolders)
        );
        address fuPrediction = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deterministicDeployerFactory, fuSalt, keccak256(fuInitcode))
                    )
                )
            )
        );
        bytes memory buybackInitcode = bytes.concat(
            type(Buyback).creationCode,
            abi.encode(
                bytes20(keccak256("git commit")),
                address(uint160(uint256(keccak256("Buyback owner")))),
                5_000,
                fuPrediction
            )
        );
        address buybackPrediction = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), deterministicDeployerFactory, buybackSalt, keccak256(buybackInitcode)
                        )
                    )
                )
            )
        );

        if (
            uint160(address(pairFor(IERC20(fuPrediction), WETH))) / Settings.ADDRESS_DIVISOR != 1
                || uint160(buybackPrediction) / Settings.ADDRESS_DIVISOR != Settings.CRAZY_BALANCE_BASIS
        ) {
            console.log("You need to recompute the salt");
            console.log("Use the tool in `.../fu/mine`:");
            console.log(string.concat("The FU inithash is ", keccak256(fuInitcode).hexlify()));
            console.log("The truncated initcode for Buyback is:");
            assembly ("memory-safe") {
                mstore(buybackInitcode, sub(mload(buybackInitcode), 0x20))
            }
            console.logBytes(buybackInitcode);
            console.log("The number of leading zeroes is", Settings.PAIR_LEADING_ZEROES);
            revert();
        }

        // Deploy FU
        deal(address(this), 5 ether);
        deal(fuTxOrigin, 5 ether);
        setBaseFee(6 wei); // causes the `isSimulation` check to pass; Medusa is unable to prank `tx.origin`
        prank(fuTxOrigin);
        (bool success, bytes memory returndata) =
            deterministicDeployerFactory.call{value: 5 ether}(bytes.concat(fuSalt, fuInitcode));
        require(success);
        require(address(uint160(bytes20(returndata))) == fuPrediction);
        fu_ = IFU(fuPrediction);
        label(address(fu_), "FU");

        // Lock initial liquidity
        IUniswapV2Pair pair = IUniswapV2Pair(fu_.pair());
        label(address(pair), "FU/WETH UniV2 Pair");
        pair.mint(buybackPrediction);

        // Deploy buyback
        (success, returndata) = deterministicDeployerFactory.call(bytes.concat(buybackSalt, buybackInitcode));
        require(success);
        require(address(uint160(bytes20(returndata))) == buybackPrediction);
        buyback_ = Buyback(buybackPrediction);

        label(DEAD, "Super dead");
    }

    function setUp() public virtual {
        deployTime = getBlockTimestamp();
        address[] memory initialActors;
        (fu, buyback, initialActors) = deployFu();
        pair = fu.pair();
        setUpActors(initialActors);
        warp(EPOCH);
    }
}
