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
import {TestPredicateHookSetup} from "./helpers/TestPredicateHookSetup.sol";

contract PredicateHookTest is TestPredicateHookSetup, TestPrep {
    function setUp() public override {
        super.setUp();
        setUpHook();
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

    function testHappyPathSwapWithSTM() public permissionedOperators prepOperatorRegistration(false) {
        uint256 expireByBlock = block.number + 100;
        string memory taskId = "unique-identifier";

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0});

        Task memory task = Task({
            taskId: taskId,
            msgSender: testSender,
            target: address(hook),
            value: 0,
            encodedSigAndArgs: abi.encodeWithSignature(
                "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)",
                router.msgSender(),
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
            expireByBlockNumber: expireByBlock
        });

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        bytes32 taskHash = serviceManager.hashTaskWithExpiry(task);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        address[] memory signerAddresses = new address[](1);
        bytes[] memory operatorSignatures = new bytes[](1);
        signerAddresses[0] = operatorOneAlias;
        operatorSignatures[0] = signature;

        PredicateMessage memory message = PredicateMessage({
            taskId: taskId,
            expireByBlockNumber: expireByBlock,
            signerAddresses: signerAddresses,
            signatures: operatorSignatures
        });

        vm.prank(address(poolManager));
        hook.beforeSwap(testSender, key, params, abi.encode(message, testSender, 0));

        assertEq(hook.getPolicy(), "x-aleo-6a52de9724a6e8f2", "Policy update failed");
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
}
