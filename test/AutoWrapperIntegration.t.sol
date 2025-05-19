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

contract AutoWrapperIntegrationTest is Test, AutoWrapperSetup, OperatorTestPrep {
    using SafeCast for uint256;
    using SafeCast for int256;

    address public liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        _setUpHooksAndPools(liquidityProvider);
        require(autoWrapper.baseCurrencyIsToken0() == true, "baseCurrency is token0");
        require(autoWrapper.baseCurrencyIsToken0ForLiquidPool() == false, "baseCurrency is not token0 for liquid pool");
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
        // USDC -> USDL
        string memory taskId = "unique-identifier";
        PoolKey memory key = getPoolKey();
        PredicateMessage memory message = getPredicateMessage(taskId, false, -1e6);
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: 1e6,
            amountOutMinimum: 1e17,
            hookData: abi.encode(message)
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency0, 1e6); // settle currency0
        params[2] = abi.encode(key.currency1, 1e17); // take currency1

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(token0.balanceOf(liquidityProvider), balance0 - 1e6, "Token0 balance should decrease by 1e6");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    }

    function testSwapZeroForOneExactOutput() public permissionedOperators prepOperatorRegistration(true) {
        // USDC -> USDL
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        uint256 amountSpecified = 1e18;
        PredicateMessage memory message =
            getPredicateMessage(taskId, false, int256(autoWrapper.wUSDL().previewWithdraw(amountSpecified)));
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountOut: amountSpecified.toUint128(),
            amountInMaximum: 1e8,
            hookData: abi.encode(message)
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
        params[2] = abi.encode(key.currency0, 1e8); // settle currency0

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.execute(abi.encode(actions, params));
    }

    function testSwapOneForZeroExactInput() public permissionedOperators prepOperatorRegistration(true) {
        // USDL -> USDC
        string memory taskId = "unique-identifier";
        PoolKey memory key = getPoolKey();
        uint256 amountSpecified = 1e18;
        PredicateMessage memory message =
            getPredicateMessage(taskId, true, -int256(autoWrapper.wUSDL().previewDeposit(amountSpecified)));
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountIn: amountSpecified.toUint128(),
            amountOutMinimum: 9e5,
            hookData: abi.encode(message)
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE), uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.TAKE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key.currency1, 1e18 + 1, true); // settle currency1
        params[1] = abi.encode(swapParams); // swap params
        params[2] = abi.encode(key.currency0, 9e5); // take currency0
        params[3] = abi.encode(key.currency1, 0); // take currency1

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(
            token1.balanceOf(liquidityProvider),
            balance1 - amountSpecified,
            "Token1 balance should decrease by amountSpecified"
        );
        require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
    }

    function testSwapOneForZeroExactOutput() public permissionedOperators prepOperatorRegistration(true) {
        string memory taskId = "unique-identifier";
        PoolKey memory key = getPoolKey();
        uint256 amountSpecified = 1e6;
        uint256 amountInMax = 2e18; // this needs to be an amount >= what is required for the swap
        PredicateMessage memory message = getPredicateMessage(taskId, true, amountSpecified.toInt128());
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountOut: amountSpecified.toUint128(),
            amountInMaximum: amountInMax.toUint128(),
            hookData: abi.encode(message)
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE),
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.TAKE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key.currency1, amountInMax, true); // settle currency1
        params[1] = abi.encode(swapParams); // swap params
        params[2] = abi.encode(key.currency0, amountSpecified); // take currency0
        params[3] = abi.encode(key.currency1, 0); // take currency1

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(actions, params));

        assertEq(
            token0.balanceOf(liquidityProvider),
            balance0 + amountSpecified,
            "Token0 balance should increase by amountSpecified"
        );
        require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
    }

    function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        uint256 amountSpecified = 1e18;
        PredicateMessage memory message =
            getPredicateMessage(taskId, true, int256(autoWrapper.wUSDL().previewWithdraw(amountSpecified)));

        // change the taskId to an invalid one
        message.taskId = "invalid-task-id";
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountOut: amountSpecified.toUint128(),
            amountInMaximum: 1e19,
            hookData: abi.encode(message)
        });

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.TAKE_ALL), uint8(Actions.SETTLE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency1, amountSpecified); // take currency1
        params[2] = abi.encode(key.currency0, 1e19); // settle currency0

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.execute(abi.encode(actions, params));
    }

    function getPredicateMessage(
        string memory taskId,
        bool zeroForOne,
        int256 amountSpecified
    ) public returns (PredicateMessage memory) {
        Task memory task = _getTask(taskId, zeroForOne, amountSpecified);
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

    function _getTask(
        string memory taskId,
        bool zeroForOne,
        int256 amountSpecified
    ) internal view returns (Task memory) {
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
}
