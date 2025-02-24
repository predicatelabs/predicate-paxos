// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { PredicateHook } from "../src/PredicateHook.sol";
import { PredicateMessage } from "@predicate/interfaces/IPredicateClient.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "test/utils/HookMiner.sol";
import { TestSetup } from "test/helpers/TestSetup.sol";

contract HookDataTest is TestSetup {
    function setUp() public override {
        super.setUp();
        setUpHook();
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
