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

contract PredicateHookIntegrationTest is PredicateHookSetup, OperatorTestPrep {
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

    function testSwapZeroForOne() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";

        PredicateMessage memory message = getPredicateMessage(taskId, true, -1e18);
        IV4Router.ExactInputSingleParams memory params = IV4Router.ExactInputSingleParams({
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

        vm.prank(address(liquidityProvider));
        swapRouter.execute(abi.encode(params));

        assertEq(token0.balanceOf(liquidityProvider), balance0 - 1e18, "Token0 balance should decrease by 1e18");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    }

    // function testSwapZeroForOneWithAuthorizedUser() public {
    //     address[] memory authorizedUsers = new address[](1);
    //     authorizedUsers[0] = makeAddr("authorizedUser");

    //     PoolKey memory key = getPoolKey();
    //     vm.prank(hook.owner());
    //     hook.addAuthorizedSwapper(authorizedUsers);

    //     vm.startPrank(authorizedUsers[0]);
    //     IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
    //     IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
    //     token0.approve(address(swapRouter), type(uint256).max);
    //     vm.stopPrank();

    //     vm.startPrank(liquidityProvider);
    //     token0.transfer(authorizedUsers[0], 1e18);
    //     vm.stopPrank();

    //     uint256 balance0 = token0.balanceOf(authorizedUsers[0]);
    //     uint256 balance1 = token1.balanceOf(authorizedUsers[0]);

    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: -1e18,
    //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //     });

    //     // vm.prank(authorizedUsers[0]);
    //     // BalanceDelta delta = swapRouter.swap(key, params, abi.encode(0)); // no predicate message
    //     // require(token0.balanceOf(authorizedUsers[0]) < balance0, "Token0 balance should decrease");
    //     // require(token1.balanceOf(authorizedUsers[0]) > balance1, "Token1 balance should increase");
    // }

    // function testSwapOneForZero() public permissionedOperators prepOperatorRegistration(true) {
    //     PoolKey memory key = getPoolKey();
    //     string memory taskId = "unique-identifier";
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: false,
    //         amountSpecified: 1e18,
    //         sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
    //     });

    //     PredicateMessage memory message = getPredicateMessage(taskId, params);

    //     IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
    //     IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
    //     uint256 balance0 = token0.balanceOf(liquidityProvider);
    //     uint256 balance1 = token1.balanceOf(liquidityProvider);

    //     // vm.prank(address(liquidityProvider));
    //     // BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
    //     // require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
    //     // require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
    // }

    // function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(true) {
    //     PoolKey memory key = getPoolKey();
    //     string memory taskId = "unique-identifier";
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: 1e18,
    //         sqrtPriceLimitX96: uint160(4_295_128_740)
    //     });

    //     PredicateMessage memory message = getPredicateMessage(taskId, params);
    //     message.taskId = "invalid-task-id";

    //     // vm.prank(address(liquidityProvider));
    //     // vm.expectRevert();
    //     // swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
    // }

    // function testSwapWithExpiredSignature() public permissionedOperators prepOperatorRegistration(true) {
    //     PoolKey memory key = getPoolKey();
    //     string memory taskId = "unique-identifier";
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: 1e18,
    //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //     });

    //     IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
    //     IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
    //     uint256 initialBalance0 = token0.balanceOf(liquidityProvider);
    //     uint256 initialBalance1 = token1.balanceOf(liquidityProvider);

    //     Task memory task = getTask(taskId, params);
    //     task.expireByBlockNumber = block.number - 1;

    //     bytes32 taskHash = serviceManager.hashTaskWithExpiry(task);

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskHash);
    //     bytes memory signature = abi.encodePacked(r, s, v);

    //     address[] memory signerAddresses = new address[](1);
    //     bytes[] memory operatorSignatures = new bytes[](1);
    //     signerAddresses[0] = operatorOneAlias;
    //     operatorSignatures[0] = signature;

    //     PredicateMessage memory message = PredicateMessage({
    //         taskId: taskId,
    //         expireByBlockNumber: task.expireByBlockNumber,
    //         signerAddresses: signerAddresses,
    //         signatures: operatorSignatures
    //     });

    //     // vm.prank(address(liquidityProvider));
    //     // vm.expectRevert();
    //     // swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));

    //     // assertEq(token0.balanceOf(liquidityProvider), initialBalance0, "Token0 balance should not change");
    //     // assertEq(token1.balanceOf(liquidityProvider), initialBalance1, "Token1 balance should not change");
    // }

    // function testDecodeHookDataEncoding() public view {
    //     string memory taskId = "task123";
    //     uint256 expireByBlockNumber = 100;

    //     address[] memory signerAddresses = new address[](2);
    //     signerAddresses[0] = 0x0000000000000000000000000000000000000123;
    //     signerAddresses[1] = 0x0000000000000000000000000000000000000456;

    //     bytes[] memory signatures = new bytes[](2);
    //     signatures[0] = hex"abcdef";
    //     signatures[1] = hex"123456";

    //     address msgSender = 0x0000000000000000000000000000000000000789; // replace
    //     uint256 msgValue = 42;

    //     PredicateMessage memory predicateMessage = PredicateMessage({
    //         taskId: taskId,
    //         expireByBlockNumber: expireByBlockNumber,
    //         signerAddresses: signerAddresses,
    //         signatures: signatures
    //     });

    //     bytes memory hookData = abi.encode(predicateMessage, msgSender, msgValue);

    //     (PredicateMessage memory decodedMsg, address decodedMsgSender, uint256 decodedMsgValue) =
    //         hook.decodeHookData(hookData);

    //     require(keccak256(bytes(decodedMsg.taskId)) == keccak256(bytes(taskId)), "TaskId mismatch");
    //     require(decodedMsg.expireByBlockNumber == expireByBlockNumber, "Expire block number mismatch");
    //     require(decodedMsg.signerAddresses.length == signerAddresses.length, "Signer addresses length mismatch");
    //     require(decodedMsg.signatures.length == signatures.length, "Signatures length mismatch");
    //     require(decodedMsgSender == msgSender, "Message sender mismatch");
    //     require(decodedMsgValue == msgValue, "Message value mismatch");

    //     for (uint256 i = 0; i < signerAddresses.length; i++) {
    //         require(decodedMsg.signerAddresses[i] == signerAddresses[i], "Signer address mismatch");
    //     }

    //     for (uint256 i = 0; i < signatures.length; i++) {
    //         require(keccak256(decodedMsg.signatures[i]) == keccak256(signatures[i]), "Signature mismatch");
    //     }
    // }

    // function testSwapWithEmptySignatures() public permissionedOperators prepOperatorRegistration(true) {
    //     PoolKey memory key = getPoolKey();
    //     string memory taskId = "unique-identifier";
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: 1e18,
    //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
    //     });

    //     IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
    //     IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
    //     uint256 initialBalance0 = token0.balanceOf(liquidityProvider);
    //     uint256 initialBalance1 = token1.balanceOf(liquidityProvider);

    //     PredicateMessage memory message = PredicateMessage({
    //         taskId: taskId,
    //         expireByBlockNumber: block.number + 100,
    //         signerAddresses: new address[](0),
    //         signatures: new bytes[](0)
    //     });

    //     bytes memory expectedError = abi.encodeWithSelector(
    //         bytes4(0x575e24b4),
    //         abi.encodeWithSelector(
    //             bytes4(0x08c379a0),
    //             abi.encode("ServiceManager.PredicateVerified: quorum threshold count cannot be zero")
    //         ),
    //         bytes4(0xa9e35b2f)
    //     );

    //     // vm.prank(address(liquidityProvider));
    //     // vm.expectRevert();
    //     // swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));

    //     // assertEq(token0.balanceOf(liquidityProvider), initialBalance0, "Token0 balance should not change");
    //     // assertEq(token1.balanceOf(liquidityProvider), initialBalance1, "Token1 balance should not change");
    // }

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
