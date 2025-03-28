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

contract AutoWrapperTest is Test, AutoWrapperSetup, OperatorTestPrep {
    address liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        setUpHooksAndPools(liquidityProvider);
        require(autoWrapper.baseCurrencyIsToken0() == true, "baseCurrency is token0");
        require(
            autoWrapper.baseCurrencyIsToken0ForPredicatePool() == false, "baseCurrency is not token0 for predicate pool"
        );
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

    function testSwapZeroForOneExactInput() public permissionedOperators prepOperatorRegistration(false) {
        // USDC -> USDL
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1e6, // for exact input
            sqrtPriceLimitX96: uint160(429_512_874_000_000_000_000_000_000_000)
        });

        IPoolManager.SwapParams memory paramsToSign = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -1e6, // for exact input
            sqrtPriceLimitX96: uint160(429_512_874_000_000_000_000_000_000_000)
        });
        PredicateMessage memory message = getPredicateMessage(taskId, paramsToSign);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(BalanceDeltaLibrary.amount0(delta) == 0, "BalanceDelta amount0 should be 0 for token0");
        require(BalanceDeltaLibrary.amount1(delta) == 0, "BalanceDelta amount1 should be 0 for token1");
        require(token0.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
        require(
            token0.balanceOf(liquidityProvider) == balance0 - uint256(-params.amountSpecified),
            "Token0 balance should decrease by the amount specified"
        );
    }

    function testSwapZeroForOneExactOutput() public permissionedOperators prepOperatorRegistration(false) {
        // USDC -> USDL
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18, // for exact output
            sqrtPriceLimitX96: uint160(429_512_874_000_000_000_000_000_000_000)
        });

        // WUSDL -> USDC
        IPoolManager.SwapParams memory paramsToSign = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: autoWrapper.getUnwrapInputRequired(uint256(params.amountSpecified)), // for exact output
            sqrtPriceLimitX96: uint160(429_512_874_000_000_000_000_000_000_000)
        });

        PredicateMessage memory message = getPredicateMessage(taskId, paramsToSign);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(BalanceDeltaLibrary.amount0(delta) == 0, "BalanceDelta amount0 should be 0 for token0");
        require(BalanceDeltaLibrary.amount1(delta) == 0, "BalanceDelta amount1 should be 0 for token1");
        require(token0.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
        require(
            token1.balanceOf(liquidityProvider) == balance1 + uint256(params.amountSpecified),
            "Token1 balance should increase by the amount specified"
        );
    }

    function testSwapOneForZeroExactInput() public permissionedOperators prepOperatorRegistration(false) {
        // USDL -> USDC
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -1e18, // for exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        IPoolManager.SwapParams memory paramsToSign = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -autoWrapper.getUnwrapInputRequired(uint256(-params.amountSpecified)),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PredicateMessage memory message = getPredicateMessage(taskId, paramsToSign);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(BalanceDeltaLibrary.amount0(delta) == 0, "BalanceDelta amount0 should be 0 for token0");
        require(BalanceDeltaLibrary.amount1(delta) == 0, "BalanceDelta amount1 should be 0 for token1");
        require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
        require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
        require(
            token1.balanceOf(liquidityProvider) == balance1 - uint256(-params.amountSpecified),
            "Token1 balance should decrease by the amount specified"
        );
    }

    function testSwapOneForZeroExactOutput() public permissionedOperators prepOperatorRegistration(false) {
        // USDL -> USDC
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e6, // for exact output
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        IPoolManager.SwapParams memory paramsToSign = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e6,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PredicateMessage memory message = getPredicateMessage(taskId, paramsToSign);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(BalanceDeltaLibrary.amount0(delta) == 0, "BalanceDelta amount0 should be 0 for token0");
        require(BalanceDeltaLibrary.amount1(delta) == 0, "BalanceDelta amount1 should be 0 for token1");
        require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
        require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
        require(
            token0.balanceOf(liquidityProvider) == balance0 + uint256(params.amountSpecified),
            "Token0 balance should increase by the amount specified"
        );
    }

    function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(false) {
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: uint160(4_295_128_740)
        });

        PredicateMessage memory message = getPredicateMessage(taskId, params);
        message.taskId = "invalid-task-id";

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
    }

    function getPredicateMessage(
        string memory taskId,
        IPoolManager.SwapParams memory params
    ) public returns (PredicateMessage memory) {
        Task memory task = getTask(taskId, params);
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

    function getTask(string memory taskId, IPoolManager.SwapParams memory params) public returns (Task memory) {
        PoolKey memory key = getPredicatePoolKey();
        return Task({
            taskId: taskId,
            msgSender: liquidityProvider,
            target: address(key.hooks),
            value: 0,
            encodedSigAndArgs: abi.encodeWithSignature(
                "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)",
                liquidityProvider,
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                address(key.hooks),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96
            ),
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });
    }

    // todo: add swap tests
}
