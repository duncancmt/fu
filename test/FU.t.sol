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

    function deployFuDependenciesFoundry() internal {
        // Deploy WETH
        bytes memory initcode = wethInit;
        vm.setNonce(wethDeployer, wethDeployerNonce);
        vm.prank(wethDeployer);
        assembly ("memory-safe") {
            if xor(weth, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(weth, "WETH");

        // Deploy the UniswapV2 factory
        initcode = univ2FactoryInit;
        vm.setNonce(univ2FactoryDeployer, univ2FactoryDeployerNonce);
        vm.prank(univ2FactoryDeployer);
        assembly ("memory-safe") {
            if xor(univ2Factory, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(univ2Factory, "Uniswap V2 Factory");

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

        // Lock initial liquidity
        IUniswapV2Pair pair = IUniswapV2Pair(fu.pair());
        label(address(pair), "FU/WETH UniV2 Pair");
        pair.mint(address(0));

        label(0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD, "Super dead");
    }

    function setUp() public virtual override {
        return deployFu();
    }

    /*
    function test_vacuous() external {}
    */
}
