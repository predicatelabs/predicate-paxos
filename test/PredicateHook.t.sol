// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredicateHook} from "../src/PredicateHook.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Task, SignatureWithSaltAndExpiry} from "@predicate/interfaces/IPredicateManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TestUtils} from "@predicate-test/helpers/utility/TestUtils.sol";
import {OperatorTestPrep} from "@predicate-test/helpers/utility/OperatorTestPrep.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PredicateHookSetup} from "./utils/PredicateHookSetup.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {PredicateClient__Unauthorized} from "@predicate/interfaces/IPredicateClient.sol";

contract PredicateHookTest is PredicateHookSetup, OperatorTestPrep {
    address liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        setUpPredicateHook(liquidityProvider);
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
        PoolKey memory key = getPoolKey();
        return Task({
            taskId: taskId,
            msgSender: liquidityProvider,
            target: address(hook),
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

    function testSwapZeroForOne() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PredicateMessage memory message = getPredicateMessage(taskId, params);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(token0.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    }

    function testSwapOneForZero() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        PredicateMessage memory message = getPredicateMessage(taskId, params);

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(token0.balanceOf(liquidityProvider) > balance0, "Token0 balance should increase");
        require(token1.balanceOf(liquidityProvider) < balance1, "Token1 balance should decrease");
    }

    function testSwapWithInvalidMessage() public permissionedOperators prepOperatorRegistration(true) {
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

    function testSwapWithExpiredSignature() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 initialBalance0 = token0.balanceOf(liquidityProvider);
        uint256 initialBalance1 = token1.balanceOf(liquidityProvider);

        Task memory task = getTask(taskId, params);
        task.expireByBlockNumber = block.number - 1;

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

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));

        assertEq(token0.balanceOf(liquidityProvider), initialBalance0, "Token0 balance should not change");
        assertEq(token1.balanceOf(liquidityProvider), initialBalance1, "Token1 balance should not change");
    }

    function testDecodeHookDataEncoding() public view {
        string memory taskId = "task123";
        uint256 expireByBlockNumber = 100;

        address[] memory signerAddresses = new address[](2);
        signerAddresses[0] = 0x0000000000000000000000000000000000000123;
        signerAddresses[1] = 0x0000000000000000000000000000000000000456;

        bytes[] memory signatures = new bytes[](2);
        signatures[0] = hex"abcdef";
        signatures[1] = hex"123456";

        address msgSender = 0x0000000000000000000000000000000000000789; // replace
        uint256 msgValue = 42;

        PredicateMessage memory predicateMessage = PredicateMessage({
            taskId: taskId,
            expireByBlockNumber: expireByBlockNumber,
            signerAddresses: signerAddresses,
            signatures: signatures
        });

        bytes memory hookData = abi.encode(predicateMessage, msgSender, msgValue);

        (PredicateMessage memory decodedMsg, address decodedMsgSender, uint256 decodedMsgValue) =
            hook.decodeHookData(hookData);

        require(keccak256(bytes(decodedMsg.taskId)) == keccak256(bytes(taskId)), "TaskId mismatch");
        require(decodedMsg.expireByBlockNumber == expireByBlockNumber, "Expire block number mismatch");
        require(decodedMsg.signerAddresses.length == signerAddresses.length, "Signer addresses length mismatch");
        require(decodedMsg.signatures.length == signatures.length, "Signatures length mismatch");
        require(decodedMsgSender == msgSender, "Message sender mismatch");
        require(decodedMsgValue == msgValue, "Message value mismatch");

        for (uint256 i = 0; i < signerAddresses.length; i++) {
            require(decodedMsg.signerAddresses[i] == signerAddresses[i], "Signer address mismatch");
        }

        for (uint256 i = 0; i < signatures.length; i++) {
            require(keccak256(decodedMsg.signatures[i]) == keccak256(signatures[i]), "Signature mismatch");
        }
    }

    function testSwapWithEmptySignatures() public permissionedOperators prepOperatorRegistration(true) {
        PoolKey memory key = getPoolKey();
        string memory taskId = "unique-identifier";
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 initialBalance0 = token0.balanceOf(liquidityProvider);
        uint256 initialBalance1 = token1.balanceOf(liquidityProvider);

        PredicateMessage memory message = PredicateMessage({
            taskId: taskId,
            expireByBlockNumber: block.number + 100,
            signerAddresses: new address[](0),
            signatures: new bytes[](0)
        });

        bytes memory expectedError = abi.encodeWithSelector(
            bytes4(0x575e24b4),
            abi.encodeWithSelector(
                bytes4(0x08c379a0),
                abi.encode("ServiceManager.PredicateVerified: quorum threshold count cannot be zero")
            ),
            bytes4(0xa9e35b2f)
        );

        vm.prank(address(liquidityProvider));
        vm.expectRevert();
        swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));

        assertEq(token0.balanceOf(liquidityProvider), initialBalance0, "Token0 balance should not change");
        assertEq(token1.balanceOf(liquidityProvider), initialBalance1, "Token1 balance should not change");
    }

    function testSetPolicy() public {
        string memory newPolicy = "new-policy";
        vm.prank(hook.owner());
        hook.setPolicy(newPolicy);
        assertEq(hook.getPolicy(), newPolicy);
    }

    function testSetPolicyUnauthorized() public {
        string memory newPolicy = "new-policy";
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.setPolicy(newPolicy);
    }

    function testSetPredicateManager() public {
        address newManager = makeAddr("new-manager");
        vm.prank(hook.owner());
        hook.setPredicateManager(newManager);
        assertEq(hook.getPredicateManager(), newManager);
    }

    function testSetPredicateManagerUnauthorized() public {
        address newManager = makeAddr("new-manager");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.setPredicateManager(newManager);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(hook.owner());
        hook.transferOwnership(newOwner);
        assertEq(hook.owner(), newOwner);
    }

    function testAddAuthorizedLP() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(hook.owner());
        hook.addAuthorizedLP(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), true);
    }

    function testRemoveAuthorizedLP() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(hook.owner());
        hook.addAuthorizedLP(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), true);

        vm.prank(hook.owner());
        hook.removeAuthorizedLP(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), false);
    }

    function testAddAuthorizedLPUnauthorized() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.addAuthorizedLP(lps);
    }
}
