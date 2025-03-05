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
import {TestPrep} from "@predicate-test/helpers/utility/TestPrep.sol";
import {STMSetup} from "@predicate-test/helpers/utility/STMSetup.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PredicateHookSetup} from "./utils/PredicateHookSetup.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";

contract PredicateHookTest is PredicateHookSetup, TestPrep {
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

    function testSwapZeroForOne() public permissionedOperators prepOperatorRegistration(false) {
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

        IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
        IERC20 token1 = IERC20(Currency.unwrap(key.currency1));
        uint256 balance0 = token0.balanceOf(liquidityProvider);
        uint256 balance1 = token1.balanceOf(liquidityProvider);

        vm.prank(address(liquidityProvider));
        BalanceDelta delta = swapRouter.swap(key, params, abi.encode(message, liquidityProvider, 0));
        require(token0.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
        require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
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
            policyID: "x-aleo-6a52de9724a6e8f2",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });
    }

    // todo: add swap tests
}
