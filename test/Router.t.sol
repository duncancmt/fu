// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Router, FU, WETH, PAIR} from "src/Router.sol";
import {Settings} from "src/core/Settings.sol";

import {UnsafeMath} from "src/lib/UnsafeMath.sol";

import {Test} from "@forge-std/Test.sol";
import {stdJson} from "@forge-std/StdJson.sol";

contract RouterTest is Test {
    using stdJson for string;
    using UnsafeMath for uint256;

    Router internal router;
    address[] internal actors;
    uint256 internal tol;

    function setUp() public {
        actors = abi.decode(vm.readFile(string.concat(vm.projectRoot(), "/airdrop.json")).parseRaw("$"), (address[]));
        for (uint256 i; i < Settings.ANTI_WHALE_DIVISOR / 2; i++) {
            actors.push(address(uint160(uint256(keccak256(abi.encodePacked("FU actor", i))))));
        }

        vm.createSelectFork(vm.envOr(string("RPC_URL"), string("http://127.0.0.1:8545")), 22016015);

        (bool success, bytes memory returndata) = 0x4e59b44847b379578588920cA78FbF26c0B4956C.call{value: 1 wei}(bytes.concat(bytes32(0), type(Router).creationCode, abi.encode(bytes20(keccak256("git commit")))));
        if (!success) {
            assembly ("memory-safe") {
                revert(add(0x20, returndata), mload(returndata))
            }
        }
        require(returndata.length == 20);
        router = Router(payable(address(uint160(bytes20(returndata)))));

        (uint256 reserveFu, uint256 reserveEth, ) = PAIR.getReserves();
        // TODO: tighten bounds
        tol = reserveFu.unsafeDivUp(reserveEth);
    }

    function testBuyExactOut(uint40 warp, uint256 actorIndex, address recipient, uint256 fuOut) external {
        address actor = actors[actorIndex % actors.length];

        warp = uint40(bound(warp, vm.getBlockTimestamp(), type(uint40).max));
        vm.warp(warp);

        (bool success, bytes memory returndata) = address(router).staticcall(abi.encodeCall(router.quoteBuyExactOut, (recipient, fuOut)));
        vm.assume(success); // TODO: handle failure
        uint256 ethIn = abi.decode(returndata, (uint256));

        uint256 beforeBalance = FU.balanceOf(recipient);

        vm.deal(actor, ethIn);
        vm.prank(actor);
        try router.buyExactOut{value: ethIn}(recipient, fuOut) {
            uint256 afterBalance = FU.balanceOf(recipient);
            assertApproxEqAbs(afterBalance - beforeBalance, fuOut, tol * (uint160(recipient) >> Settings.ADDRESS_SHIFT));
        } catch Error(string memory reason) {
            if (recipient == address(PAIR)) {
                assertEq(reason, "UniswapV2: TRANSFER_FAILED");
            } else if (recipient == address(FU) || recipient == address(WETH)) {
                assertEq(reason, "UniswapV2: INVALID_TO");
            } else {
                assertLe(fuOut, tol * (uint160(recipient) >> Settings.ADDRESS_SHIFT));
                assertEq(reason, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
            }
        } catch {
            assertGe(beforeBalance + fuOut, FU.whaleLimit(recipient));
        }
    }

    function testBuyExactOutUnderfund(uint40 warp, uint256 actorIndex, address recipient, uint256 fuOut) external {
        address actor = actors[actorIndex % actors.length];

        warp = uint40(bound(warp, vm.getBlockTimestamp(), type(uint40).max));
        vm.warp(warp);

        (bool success, bytes memory returndata) = address(router).staticcall(abi.encodeCall(router.quoteBuyExactOut, (recipient, fuOut)));
        vm.assume(success); // TODO: handle failure
        uint256 ethIn = abi.decode(returndata, (uint256));

        vm.deal(actor, ethIn);
        vm.prank(actor);
        vm.expectRevert(bytes(""));
        router.buyExactOut{value: ethIn - 1}(recipient, fuOut);
    }
}
