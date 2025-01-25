// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFU} from "src/interfaces/IFU.sol";
import {FU} from "src/FU.sol";
import {Settings} from "src/core/Settings.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";

import {QuickSort} from "script/QuickSort.sol";
import {ItoA} from "script/ItoA.sol";

import {StdAssertions} from "@forge-std/StdAssertions.sol";
import {StdInvariant} from "@forge-std/StdInvariant.sol";
import {Vm} from "@forge-std/Vm.sol";

import "./EnvironmentConstants.sol";

import {console} from "@forge-std/console.sol";

address constant DEAD = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;
uint256 constant EPOCH = 1740721485;

abstract contract Common {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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
}

abstract contract Bound {
    // Copied directly from Foundry
    function _bound(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256 result) {
        require(min <= max, "StdUtils bound(uint256,uint256,uint256): Max is less than min.");
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x >= min && x <= max) return x;

        uint256 size = max - min + 1;

        // If the value is 0, 1, 2, 3, wrap that to min, min+1, min+2, min+3. Similarly for the UINT256_MAX side.
        // This helps ensure coverage of the min/max values.
        if (x <= 3 && size > x) return min + x;
        if (x >= type(uint256).max - 3 && size > type(uint256).max - x) return max - (type(uint256).max - x);

        // Otherwise, wrap x into the range [min, max], i.e. the range is inclusive.
        if (x > max) {
            uint256 diff = x - max;
            uint256 rem = diff % size;
            if (rem == 0) return max;
            result = min + rem - 1;
        } else if (x < min) {
            uint256 diff = min - x;
            uint256 rem = diff % size;
            if (rem == 0) return min;
            result = max - rem + 1;
        }
    }

    function bound(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256 result) {
        result = _bound(x, min, max);
        console.log("Bound result", result);
    }

    function _bound(int256 x, int256 min, int256 max) internal pure virtual returns (int256 result) {
        require(min <= max, "StdUtils bound(int256,int256,int256): Max is less than min.");

        // Shifting all int256 values to uint256 to use _bound function. The range of two types are:
        // int256 : -(2**255) ~ (2**255 - 1)
        // uint256:     0     ~ (2**256 - 1)
        // So, add 2**255, INT256_MIN_ABS to the integer values.
        //
        // If the given integer value is -2**255, we cannot use `-uint256(-x)` because of the overflow.
        // So, use `~uint256(x) + 1` instead.
        uint256 _x = x < 0 ? (uint256(type(int256).min) - ~uint256(x) - 1) : (uint256(x) + uint256(type(int256).min));
        uint256 _min = min < 0 ? (uint256(type(int256).min) - ~uint256(min) - 1) : (uint256(min) + uint256(type(int256).min));
        uint256 _max = max < 0 ? (uint256(type(int256).min) - ~uint256(max) - 1) : (uint256(max) + uint256(type(int256).min));

        uint256 y = _bound(_x, _min, _max);

        // To move it back to int256 value, subtract INT256_MIN_ABS at here.
        result = y < uint256(type(int256).min) ? int256(~(uint256(type(int256).min) - y) + 1) : int256(y - uint256(type(int256).min));
    }

    function bound(int256 x, int256 min, int256 max) internal pure virtual returns (int256 result) {
        result = _bound(x, min, max);
        console.log("Bound result", ItoA.itoa(result));
    }
}

interface ListOfInvariants {
    function invariant_nonNegativeRebase() external;
    function invariant_delegatesNotChanged() external;
}

contract FUGuide is StdAssertions, Common, Bound, ListOfInvariants {
    IFU internal fu;
    address[] internal actors;
    mapping(address => bool) internal isActor;
    mapping(address => uint256) internal lastBalance;
    mapping(address => address) internal shadowDelegates;

    constructor (IFU fu_, address[] memory actors_) {
        fu = fu_;
        actors = actors_;

        lastBalance[DEAD] = fu.balanceOf(DEAD);
        address pair = fu.pair();
        actors.push(pair);

        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            isActor[actor] = true;
            lastBalance[actor] = fu.balanceOf(actor);
        }
    }

    function callOptionalReturn(bytes memory data) internal returns (bool success, bytes memory returndata) {
        (success, returndata) = address(fu).call(data);
        success = success && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    function getActor(uint256 actorIndex) internal returns (address actor) {
        actor = actors[actorIndex % actors.length];
        uint256 balance = fu.balanceOf(actor);
        assertGe(balance, lastBalance[actor], "negative rebase");
        lastBalance[actor] = balance;
        assertEq(fu.delegates(actor), shadowDelegates[actor]);
    }

    function maybeCreateActor(address newActor) internal {
        if (newActor == DEAD) {
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
        assertNotEq(actor, DEAD);
        assertTrue(isActor[actor]);
        lastBalance[actor] = fu.balanceOf(actor);
        shadowDelegates[actor] = fu.delegates(actor);
    }

    function addActor(address newActor) external {
        assume(newActor != DEAD);
        maybeCreateActor(newActor);
        saveActor(newActor);
    }

    function warp(uint24 incr) external {
        warp(getBlockTimestamp() + incr);
    }

    function transfer(uint256 actorIndex, address to, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        }
        if (actor == fu.pair()) {
            assume(amount <= fu.balanceOf(actor));
        }
        maybeCreateActor(to);

        prank(actor);
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.transfer, (to, amount)));

        // TODO: handle failure and assert that we fail iff the reason is expected
        if (!success) {
            // TODO: assert that there are no state modifications
            return;
        }

        saveActor(actor);
        saveActor(to);
    }

    function delegate(uint256 actorIndex, address delegatee) external {
        address actor = getActor(actorIndex);
        assume(actor != fu.pair());
        maybeCreateActor(delegatee);

        prank(actor);
        fu.delegate(delegatee); // ERC5805 requires that this function return nothing or revert

        saveActor(actor);
        saveActor(delegatee);
    }

    function burn(uint256 actorIndex, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        }
        assume(actor != fu.pair() || amount == 0);

        prank(actor);
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.burn, (amount)));

        // TODO: handle failure and assert that we fail iff the reason is expected
        if (!success) {
            // TODO: assert that there are no state modifications
            return;
        }

        saveActor(actor);
    }

    function deliver(uint256 actorIndex, uint256 amount, bool boundAmount) external {
        address actor = getActor(actorIndex);
        if (boundAmount) {
            amount = bound(amount, 0, fu.balanceOf(actor));
        }
        assume(actor != fu.pair() || amount == 0);

        prank(actor);
        (bool success, bytes memory returndata) = callOptionalReturn(abi.encodeCall(fu.deliver, (amount)));

        // TODO: handle failure and assert that we fail iff the reason is expected
        if (!success) {
            // TODO: assert that there are no state modifications
            return;
        }

        saveActor(actor);
    }

    function invariant_nonNegativeRebase() external view override {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            // TODO: this should eventually fail when an account reaches the whale limit and somebody calls `burn`
            assertGe(fu.balanceOf(actor), lastBalance[actor], "negative rebase");
        }
    }

    function invariant_delegatesNotChanged() external view override {
        for (uint256 i; i < actors.length; i++) {
            address actor = actors[i];
            assertEq(fu.delegates(actor), shadowDelegates[actor], "delegates mismatch");
        }
    }
}

contract FUInvariants is StdInvariant, Common, ListOfInvariants {
    using QuickSort for address[];

    bool public constant IS_TEST = true;
    FUGuide internal guide;

    function deployFuDependenciesFoundry() internal {
        // Deploy WETH
        bytes memory initcode = wethInit;
        setNonce(wethDeployer, wethDeployerNonce);
        prank(wethDeployer);
        assembly ("memory-safe") {
            if xor(weth, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(weth, "WETH");
        excludeContract(weth);

        // Deploy the UniswapV2 factory
        initcode = univ2FactoryInit;
        setNonce(univ2FactoryDeployer, univ2FactoryDeployerNonce);
        prank(univ2FactoryDeployer);
        assembly ("memory-safe") {
            if xor(univ2Factory, create(0x00, add(0x20, initcode), mload(initcode))) { revert(0x00, 0x00) }
        }
        label(univ2Factory, "Uniswap V2 Factory");
        excludeContract(univ2Factory);

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

    function deployFu() internal returns (IFU fu, address[] memory initialHolders) {
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

        // Deploy FU
        bytes memory initcode = bytes.concat(
            type(FU).creationCode,
            abi.encode(bytes20(keccak256("git commit")), string("I am totally an SVG image, I promise"), initialHolders)
        );
        console.log("FU mock inithash");
        console.logBytes32(keccak256(initcode));
        deal(address(this), 5 ether);
        deal(fuTxOrigin, 5 ether);
        setBaseFee(6 wei); // causes the `isSimulation` check to pass; Medusa is unable to prank `tx.origin`
        prank(fuTxOrigin);
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

        label(DEAD, "Super dead");
    }

    function setUp() external {
        (IFU fu, address[] memory actors) = deployFu();
        guide = new FUGuide(fu, actors);
        warp(EPOCH);
    }

    function invariant_nonNegativeRebase() external override {
        return guide.invariant_nonNegativeRebase();
    }

    function invariant_delegatesNotChanged() external override {
        return guide.invariant_delegatesNotChanged();
    }
}
