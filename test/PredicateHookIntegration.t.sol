// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredicateHook} from "../src/PredicateHook.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Task} from "@predicate/interfaces/IPredicateManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {OperatorTestPrep} from "@predicate-test/helpers/utility/OperatorTestPrep.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PredicateHookSetup} from "./utils/PredicateHookSetup.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {Test} from "forge-std/Test.sol";

contract PredicateHookIntegrationTest is Test, PredicateHookSetup, OperatorTestPrep {
    address public liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        _setUpPredicateHook(liquidityProvider);
    }

    modifier permissionedOperators() {
        vm.startPrank(address(this));
        address[] memory operators = new address[](2);
        operators[0] = operatorOne;
        operators[1] = operatorTwo;
        serviceManager.addPermissionedOperators(operators);
        vm.stopPrank();
        _;
    }

    function testSwapZeroForOneExactInput() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";

        PredicateMessage memory message = getPredicateMessage(taskId, true, -1e18);
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: 1e18,
            amountOutMinimum: 1e17,
            hookData: abi.encode(message, liquidityProvider, 0)
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(key.currency0, 1e18);
        params[2] = abi.encode(key.currency1, 1e17);

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(liquidityProvider), balance0 - 1e18, "Token0 balance should decrease by 1e18");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    }

    function testSwapZeroForOneWithAuthorizedUser() public {
        address[] memory authorizedUsers = new address[](1);
        authorizedUsers[0] = makeAddr("authorizedUser");

        PoolKey memory key = getPoolKey();
        vm.prank(hook.owner());
        hook.addAuthorizedSwapper(authorizedUsers);

        vm.startPrank(authorizedUsers[0]);
        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        token0.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        token0.transfer(authorizedUsers[0], 1e18);
        vm.stopPrank();

        uint256 balance0 = token0.balanceOf(authorizedUsers[0]);
        uint256 balance1 = token1.balanceOf(authorizedUsers[0]);

        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: 1e18,
            amountOutMinimum: 1e17,
            hookData: abi.encode(0)
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency0, 1e18); // settle currency0
        params[2] = abi.encode(key.currency1, 1e17); // settle currency1

        vm.prank(authorizedUsers[0]);
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(authorizedUsers[0]), balance0 - 1e18, "Token0 balance should decrease by 1e18");
        require(token1.balanceOf(authorizedUsers[0]) > balance1, "Token1 balance should increase");
    }

    function testSwapOneForZeroExactOutput() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";

        PredicateMessage memory message = getPredicateMessage(taskId, false, 1e18);
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountOut: 1e18,
            amountInMaximum: 1e19,
            hookData: abi.encode(message, liquidityProvider, 0)
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.TAKE_ALL), uint8(Actions.SETTLE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(key.currency0, 1e18);
        params[2] = abi.encode(key.currency1, 1e19);

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(liquidityProvider), balance0, "Token0 balance should not change");
        assertEq(token1.balanceOf(liquidityProvider), balance1, "Token1 balance should not change");
    }

    function testSwapWithEmptySignatures() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountOut: 1e18,
            amountInMaximum: 1e19,
            hookData: abi.encode(0)
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.TAKE_ALL), uint8(Actions.SETTLE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(key.currency0, 1e18);
        params[2] = abi.encode(key.currency1, 1e19);

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(liquidityProvider), balance0 + 1e18, "Token0 balance should increase by 1e18");
        require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
    }

    function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";

        PredicateMessage memory message = getPredicateMessage(taskId, false, 1e18);

        message.taskId = "wrong-identifier";
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountOut: 1e18,
            amountInMaximum: 1e17,
            hookData: abi.encode(message, liquidityProvider, 0)
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(key.currency0, 1e17);
        params[2] = abi.encode(key.currency1, 1e18);

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.execute(abi.encode(actions, params));
    }

    function getPredicateMessage(
        string memory taskId,
        bool zeroForOne,
        int256 amountSpecified
    ) public returns (PredicateMessage memory) {
        Task memory task = getTask(taskId, zeroForOne, amountSpecified);
        bytes32 taskHash = serviceManager.hashTaskWithExpiry(task);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory operatorSignatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        operatorSignatures[0] = signature;

        PredicateMessage memory message = PredicateMessage({
            taskId: taskId,
            expireByBlockNumber: task.expireByBlockNumber,
            signerAddresses: signerAddresses,
            signatures: operatorSignatures
        });

        return message;
    }

    function getTask(string memory taskId, bool zeroForOne, int256 amountSpecified) public returns (Task memory) {
        PoolKey memory key = getPoolKey();
        return Task({
            taskId: taskId,
            msgSender: liquidityProvider,
            target: address(hook),
            value: 0,
            encodedSigAndArgs: abi.encodeWithSignature(
                "_beforeSwap(address,address,address,uint24,int24,address,bool,int256)",
                liquidityProvider,
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                address(key.hooks),
                zeroForOne,
                amountSpecified
            ),
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });
    }
}
