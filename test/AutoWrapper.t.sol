// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutoWrapper} from "../src/AutoWrapper.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Task} from "@predicate/interfaces/IPredicateManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {OperatorTestPrep} from "@predicate-test/helpers/utility/OperatorTestPrep.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {AutoWrapperSetup} from "./utils/AutoWrapperSetup.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

contract AutoWrapperTest is Test, AutoWrapperSetup, OperatorTestPrep {
    using SafeCast for uint256;
    using SafeCast for int256;

    address public liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        _setUpHooksAndPools(liquidityProvider);
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
        string memory taskId = "unique-identifier";
        PoolKey memory key = getPoolKey();
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
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency0, 1e18); // settle currency0
        params[2] = abi.encode(key.currency1, 1e17); // settle currency1

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(liquidityProvider), balance0 - 1e18, "Token0 balance should decrease by 1e18");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    }

    function testSwapZeroForOneExactOutput() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        uint256 amountSpecified = 1e18;
        PredicateMessage memory message =
            getPredicateMessage(taskId, true, autoWrapper.getUnwrapInputRequired(amountSpecified));
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountOut: amountSpecified.toUint128(),
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
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency1, amountSpecified); // take currency1
        params[2] = abi.encode(key.currency0, 1e19); // settle currency0

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(
            token0.balanceOf(liquidityProvider),
            balance1 + amountSpecified,
            "Token1 balance should increase by amountSpecified"
        );
        require(token1.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
    }

    function testSwapOneForZeroExactInput() public permissionedOperators prepOperatorRegistration(false) {
        // TODO: fix this test
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -1e18, // for exact input
            sqrtPriceLimitX96: uint160(TickMath.MAX_SQRT_PRICE - 1)
        });

        IPoolManager.SwapParams memory paramsToSign = params;
        paramsToSign.amountSpecified = -autoWrapper.getUnwrapInputRequired(uint256(-params.amountSpecified));

        PredicateMessage memory message = getPredicateMessage(taskId, true, -1e18);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        // vm.prank(address(liquidityProvider));
        // BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        // require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
        // require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
        // require(
        //     token1.balanceOf(liquidityProvider) == balance1 - uint256(-params.amountSpecified),
        //     "Token1 balance should decrease by the amount specified"
        // );
    }

    function testSwapOneForZeroExactOutput() public permissionedOperators prepOperatorRegistration(false) {
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e18, // for exact output
            sqrtPriceLimitX96: uint160(TickMath.MAX_SQRT_PRICE - 1)
        });

        IPoolManager.SwapParams memory paramsToSign = params;
        paramsToSign.amountSpecified = params.amountSpecified;

        PredicateMessage memory message = getPredicateMessage(taskId, params.zeroForOne, params.amountSpecified);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        // vm.prank(address(liquidityProvider));
        // BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        // require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
        // require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
        // require(
        //     token0.balanceOf(liquidityProvider) == balance0 + uint256(params.amountSpecified),
        //     "Token0 balance should increase by the amount specified"
        // );
    }

    function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(false) {
        // TODO: fix this test
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: uint160(4_295_128_740)
        });

        PredicateMessage memory message = getPredicateMessage(taskId, params.zeroForOne, params.amountSpecified);
        message.taskId = "invalid-task-id";

        // vm.prank(address(liquidityProvider));
        // vm.expectRevert();
        // swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
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
        PoolKey memory key = getPredicatePoolKey();
        return Task({
            taskId: taskId,
            msgSender: liquidityProvider,
            target: address(predicateHook),
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

    // todo: add swap tests
}
