// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFU} from "src/interfaces/IFU.sol";
import {FU} from "src/FU.sol";
import {Settings} from "src/core/Settings.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";

import {QuickSort} from "script/QuickSort.sol";

import {Test} from "@forge-std/Test.sol";
import {Boilerplate} from "./Boilerplate.sol";

import "./EnvironmentConstants.sol";

import {console} from "@forge-std/console.sol";

contract FUTest is Boilerplate, Test {
    using QuickSort for address[];

    IFU internal fu;
    address[] internal actors;
    mapping(address => bool) internal isActor;
    mapping(address => uint256) internal lastBalance;
    mapping(address => address) internal shadowDelegates;

    function deployFuDependenciesFoundry() internal {
        // Deploy WETH
        bytes memory initcode = wethInit;
        vm.setNonce(wethDeployer, wethDeployerNonce);
        vm.prank(wethDeployer);
        assembly ("memory-safe") {
            if xor(weth, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(weth, "WETH");
        excludeContract(weth);

        // Deploy the UniswapV2 factory
        initcode = univ2FactoryInit;
        vm.setNonce(univ2FactoryDeployer, univ2FactoryDeployerNonce);
        vm.prank(univ2FactoryDeployer);
        assembly ("memory-safe") {
            if xor(univ2Factory, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(univ2Factory, "Uniswap V2 Factory");
        excludeContract(univ2Factory);

        // Optionally deploy the deployment proxy, if it doesn't exist
        if (deterministicDeployerFactory.codehash != 0x2fa86add0aed31f33a762c9d88e807c475bd51d0f52bd0955754b2608f7e4989)
        {
            initcode = deterministicDeployerFactoryInit;
            vm.setNonce(deterministicDeployerFactoryDeployer, deterministicDeployerFactoryDeployerNonce);
            vm.prank(deterministicDeployerFactoryDeployer);
            assembly ("memory-safe") {
                if xor(deterministicDeployerFactory, create(0x00, add(0x20, initcode), mload(initcode))) {
                    revert(0x00, 0x00)
                }
            }
            label(deterministicDeployerFactory, "Create2Deployer");
        }
    }

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

    function deployFuDependencies() internal virtual {
        return deployFuDependenciesFoundry();
    }

    function deployFu() internal {
        address[] memory initialHolders = new address[](Settings.ANTI_WHALE_DIVISOR * 2);
        for (uint256 i; i < initialHolders.length; i++) {
            // Generate unique addresses
            address holder;
            assembly ("memory-safe") {
                mstore(0x00, add("FU holder", i))
                holder := keccak256(0x00, 0x20)
            }
            initialHolders[i] = holder;
            isActor[holder] = true;
        }
        initialHolders.quickSort();
        actors = initialHolders;

        vm.chainId(1);

        deployFuDependencies();

        // Deploy FU
        bytes memory initcode = bytes.concat(
            type(FU).creationCode,
            abi.encode(bytes20(keccak256("git commit")), string("I am totally an SVG image, I promise"), initialHolders)
        );
        console.log("FU mock inithash");
        console.logBytes32(keccak256(initcode));
        vm.deal(address(this), 5 ether);
        vm.deal(fuTxOrigin, 5 ether);
        vm.fee(6 wei); // causes the `isSimulation` check to pass; Medusa is unable to prank `tx.origin`
        vm.prank(fuTxOrigin);
        (bool success, bytes memory returndata) = deterministicDeployerFactory.call{value: 5 ether}(
            bytes.concat(bytes32(0x000000000000000000000000000000000000000000000000000000007b69935d), initcode)
        );
        require(success);
        fu = IFU(payable(address(uint160(bytes20(returndata)))));
        label(address(fu), "FU");
        excludeContract(address(fu));

        // Lock initial liquidity
        IUniswapV2Pair pair = IUniswapV2Pair(fu.pair());
        label(address(pair), "FU/WETH UniV2 Pair");
        pair.mint(address(0));
        excludeContract(address(pair));

        label(0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD, "Super dead");

        lastBalance[address(pair)] = fu.balanceOf(address(pair));
        lastBalance[0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD] = fu.balanceOf(0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD);
        for (uint256 i; i < initialHolders.length; i++) {
            address initialHolder = initialHolders[i];
            lastBalance[initialHolder] = fu.balanceOf(initialHolder);
        }
    }

    function setUp() public virtual override {
        deployFu();
        targetContract(address(this));
    }

    function callOptionalReturn(bytes memory data) internal {
        (bool success, bytes memory returndata) = address(fu).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(0x20, returndata), mload(returndata))
            }
        }
        if (returndata.length != 0) {
            require(returndata.length == 32);
            success = abi.decode(data, (bool));
            require(success, "returned `false` to signal failure");
        } else {
            require(address(fu).code.length != 0);
        }
    }

    function getActor(uint256 actorIndex) internal returns (address actor) {
        actor = actors[actorIndex % actors.length];
        uint256 balance = fu.balanceOf(actor);
        assertGe(balance, lastBalance[actor], "negative rebase");
        lastBalance[actor] = balance;
        assertEq(fu.delegates(actor), shadowDelegates[actor]);
    }

    function maybeCreateActor(address newActor) internal {
        if (newActor == fu.pair()) {
            return;
        }
        if (newActor == 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD) {
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

    function saveActor(address actor) internal {
        if (actor != fu.pair()) {
            assertNotEq(actor, 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD);
            assertTrue(isActor[actor]);
        }
        lastBalance[actor] = fu.balanceOf(actor);
        shadowDelegates[actor] = fu.delegates(actor);
    }

    function addActor(address newActor) external {
        assume(newActor != 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD);
        maybeCreateActor(newActor);
        saveActor(newActor);
    }

    function transfer(uint256 actorIndex, address to, uint256 amount) external {
        address actor = getActor(actorIndex);
        maybeCreateActor(to);

        vm.prank(actor);
        callOptionalReturn(abi.encodeCall(fu.transfer, (to, amount)));

        saveActor(actor);
        saveActor(to);
    }

    function delegate(uint256 actorIndex, address delegatee) external {
        address actor = getActor(actorIndex);
        maybeCreateActor(delegatee);

        vm.prank(actor);
        fu.delegate(delegatee); // ERC5805 requires that this function return nothing or revert

        saveActor(actor);
        saveActor(delegatee);
    }

    function burn(uint256 actorIndex, uint256 amount) external {
        address actor = getActor(actorIndex);

        vm.prank(actor);
        callOptionalReturn(abi.encodeCall(fu.burn, (amount)));

        saveActor(actor);
    }

    function deliver(uint256 actorIndex, uint256 amount) external {
        address actor = getActor(actorIndex);

        vm.prank(actor);
        callOptionalReturn(abi.encodeCall(fu.deliver, (amount)));

        saveActor(actor);
    }


    function test_vacuous() external pure {}
    function invariant_vacuous() external pure {}
}
