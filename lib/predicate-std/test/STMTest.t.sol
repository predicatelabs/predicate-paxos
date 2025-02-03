// SPDX-License-Identifier: MIT
pragma solidity =0.8.12;

import "./helpers/utility/TestUtils.sol";
import "./helpers/utility/STMSetup.sol";
import "./helpers/utility/TestPrep.sol";
import {PredicateMessage} from "../src/interfaces/IPredicateClient.sol";
import "forge-std/console.sol";

contract STMTest is TestPrep, STMSetup {
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
        uint256 amount = 10;

        bytes32 messageHash = TestUtils.hashTaskSTM(
            Task({
                taskId: taskId,
                msgSender: testSender,
                target: address(metaCoinContract),
                value: 0,
                encodedSigAndArgs: abi.encodeWithSignature("_sendCoin(address,uint256)", testReceiver, amount),
                policyID: "testPolicy",
                quorumThresholdCount: 1,
                expireByBlockNumber: expireByBlock
            })
        );

        bytes memory signature;

        // register operator and sign message hash
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, messageHash);
        signature = abi.encodePacked(r, s, v);

        // create
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
        vm.prank(testSender);
        metaCoinContract.sendCoin(testReceiver, amount, message);
        assertEq(metaCoinContract.getBalance(testReceiver), 10, "receiver balance should be 10 after receiving");
        assertEq(
            metaCoinContract.getBalance(testSender), 9_999_999_999_990, "sender balance should be 9900 after sending"
        );
    }
}
