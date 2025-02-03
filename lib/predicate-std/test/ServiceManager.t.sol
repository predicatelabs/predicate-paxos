// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {ServiceManager} from "../src/ServiceManager.sol";
import {Task} from "../src/interfaces/IPredicateManager.sol";
import {MockClient} from "./helpers/MockClient.sol";
import {MockProxy} from "./helpers/MockProxy.sol";
import {MockProxyAdmin} from "./helpers/MockProxyAdmin.sol";
import {MockStakeRegistry} from "./helpers/MockStakeRegistry.sol";
import {MockDelegationManager} from "./helpers/MockDelegationManager.sol";
import {IPauserRegistry} from "./helpers/eigenlayer/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "./helpers/eigenlayer/interfaces/IDelegationManager.sol";
import {MockStrategyManager} from "./helpers/MockStrategyManager.sol";
import {MockEigenPodManager} from "./helpers/MockEigenPodManager.sol";
import "./helpers/utility/TestUtils.sol";
import "./helpers/utility/ServiceManagerSetup.sol";
import "./helpers/utility/TestPrep.sol";

contract ServiceManagerTest is TestPrep, ServiceManagerSetup {
    modifier permissionedOperators() {
        vm.startPrank(address(this));
        address[] memory operators = new address[](2);
        operators[0] = operatorOne;
        operators[1] = operatorTwo;
        serviceManager.addPermissionedOperators(operators);
        vm.stopPrank();
        _;
    }

    function testCanDeploySocialGraph() public {
        serviceManager.deploySocialGraph("sg_2", "sampleConfig");
        string memory socialGraphConfig = serviceManager.idToSocialGraph("sg_2");
        assertEq(socialGraphConfig, "sampleConfig");
    }

    function testCanDeployPolicy() public {
        serviceManager.deployPolicy("sg-policy-2", "samplePolicy", 1);
        string memory policyConfig = serviceManager.idToPolicy("sg-policy-2");
        assertEq(policyConfig, "samplePolicy");
    }

    function testNoDuplicateSocialGraphDeploy() public {
        serviceManager.deploySocialGraph("sg_2", "sampleConfig");
        vm.expectRevert();
        serviceManager.deploySocialGraph("sg_2", "sampleConfig");
    }

    function testNoDuplicatePolicyDeploy() public {
        serviceManager.deployPolicy("sg-policy-2", "samplePolicy", 1);
        vm.expectRevert();
        serviceManager.deployPolicy("sg-policy-2", "samplePolicy", 1);
    }

    function testOperatorCanRegisterOperator() public permissionedOperators prepOperatorRegistration(false) {
        serviceManager.addStrategy(strategyAddrOne, 0, 0);

        vm.expectEmit(true, true, true, true);
        emit OperatorRegistered(operatorOne);
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);
    }

    function testOwnerCanRemoveOperator() public permissionedOperators prepOperatorRegistration(false) {
        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        vm.expectEmit(true, true, true, true);
        emit OperatorRemoved(operatorOne);

        serviceManager.deregisterOperatorFromAVS(operatorOne);
        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 2);
    }

    function testRandomAddrCannotRemoveOperator() public permissionedOperators prepOperatorRegistration(false) {
        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        vm.expectRevert();
        vm.prank(randomAddr);
        serviceManager.deregisterOperatorFromAVS(operatorOne);
    }

    function testOperatorCanChangeAlias() public permissionedOperators prepOperatorRegistration(false) {
        vm.startPrank(operatorOne);
        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);

        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        address operatorRegistrationAddress = serviceManager.signingKeyToOperator(operatorOneAlias);
        assertEq(operatorRegistrationAddress, operatorOne);

        serviceManager.rotatePredicateSigningKey(operatorOneAlias, newAlias);

        address newOperatorRegistrationAddress = serviceManager.signingKeyToOperator(newAlias);
        assertEq(newOperatorRegistrationAddress, operatorOne);
        vm.stopPrank();
    }

    function testRandomAddrCanNotChangeAlias() public permissionedOperators prepOperatorRegistration(false) {
        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        address operatorRegistrationAddress = serviceManager.signingKeyToOperator(operatorOneAlias);
        assertEq(operatorRegistrationAddress, operatorOne);

        vm.expectRevert();
        vm.prank(randomAddr);

        serviceManager.rotatePredicateSigningKey(operatorOneAlias, newAlias);
    }

    function testOperatorCanNotChangeOtherAlias() public permissionedOperators prepOperatorRegistration(false) {
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        vm.prank(operatorTwo);
        serviceManager.registerOperatorToAVS(operatorTwoAlias, operatorTwoSignature);

        (, ServiceManager.OperatorStatus statusTwo) = serviceManager.operators(operatorTwo);
        assertEq(uint256(statusTwo), 1);

        vm.expectRevert();
        vm.prank(operatorTwo);

        serviceManager.rotatePredicateSigningKey(operatorOneAlias, newAlias);
    }

    function testOwnerCanAddStrategy() public {
        vm.expectEmit(true, true, true, true);
        emit StrategyAdded(strategyAddrOne);

        serviceManager.addStrategy(strategyAddrOne, 0, 0);
        address strategyRetrieved = serviceManager.strategies(0);
        assertEq(strategyRetrieved, strategyAddrOne);
    }

    function testRandomAddrCanNotAddStrategy() public {
        vm.expectRevert();
        vm.prank(randomAddr);
        serviceManager.addStrategy(strategyAddrOne, 0, 0);
    }

    function testCanNotAddInvalidStrategy() public {
        vm.expectRevert();
        serviceManager.addStrategy(strategyAddrOne, 0, 100);
    }

    function testOwnerCanRemoveStrategy() public {
        serviceManager.addStrategy(strategyAddrOne, 0, 0);
        serviceManager.addStrategy(strategyAddrTwo, 0, 1);

        address strategyRetrieved = serviceManager.strategies(1);
        assertEq(strategyRetrieved, strategyAddrTwo);

        vm.expectEmit(true, true, true, true);
        emit StrategyRemoved(strategyAddrTwo);

        serviceManager.removeStrategy(strategyAddrTwo);

        vm.expectRevert();
        strategyRetrieved = serviceManager.strategies(1);
    }

    function testRandomAddrCanNotRemoveStrategy() public {
        serviceManager.addStrategy(strategyAddrOne, 0, 0);
        serviceManager.addStrategy(strategyAddrTwo, 0, 1);

        address strategyRetrieved = serviceManager.strategies(1);
        assertEq(strategyRetrieved, strategyAddrTwo);

        vm.expectRevert();
        vm.prank(randomAddr);
        serviceManager.removeStrategy(strategyAddrTwo);
    }

    function testUpdateOperatorsForQuorumZeroStake() public permissionedOperators prepOperatorRegistration(false) {
        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);

        serviceManager.addStrategy(strategyAddrOne, 0, 0);

        address[][] memory operatorsPerQuorum = new address[][](1);
        address[] memory addresses = new address[](1);
        addresses[0] = operatorOne;
        operatorsPerQuorum[0] = addresses;
        bytes memory quorumNumbers = new bytes(1);
        uint256 num = 1;
        quorumNumbers[0] = bytes1(abi.encodePacked(num));

        vm.expectEmit(true, true, true, true);
        emit OperatorsStakesUpdated(operatorsPerQuorum, quorumNumbers);

        serviceManager.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);

        (, status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 1);
    }

    function testCanNotUpdateForQuorumInvalidOperator() public {
        address[][] memory operatorsPerQuorum = new address[][](1);
        address[] memory addresses = new address[](1);
        addresses[0] = randomAddr;
        operatorsPerQuorum[0] = addresses;
        bytes memory quorumNumbers = new bytes(1);
        uint256 num = 1;
        quorumNumbers[0] = bytes1(abi.encodePacked(num));

        vm.expectRevert();
        serviceManager.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
    }

    function testCanNotUpdateQuorumWithInvalidArray() public {
        address[][] memory operatorsPerQuorum = new address[][](2);
        address[] memory addresses = new address[](1);
        addresses[0] = operatorOne;
        operatorsPerQuorum[0] = addresses;
        operatorsPerQuorum[1] = addresses;
        bytes memory quorumNumbers = new bytes(1);
        uint256 num = 1;
        quorumNumbers[0] = bytes1(abi.encodePacked(num));

        vm.expectRevert();
        serviceManager.updateOperatorsForQuorum(operatorsPerQuorum, quorumNumbers);
    }

    function testCannotUseSpentTask() public permissionedOperators prepOperatorRegistration(false) {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        bytes memory signature;

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        bool result = serviceManager.validateSignatures(task, signers, signatures);
        assertTrue(result, "First execution should succeed");

        vm.expectRevert();
        serviceManager.validateSignatures(task, signers, signatures);

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        vm.expectRevert();
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function testCannotReplaySignatures() public permissionedOperators prepOperatorRegistration(false) {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        bytes memory signature;

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        bool result = serviceManager.validateSignatures(task, signers, signatures);
        assertTrue(result, "First execution is expected to succeed");

        vm.expectRevert();
        serviceManager.validateSignatures(task, signers, signatures);

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        vm.expectRevert();
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function cannotSupplySignaturesToTaskWithDifferentDigest()
        public
        permissionedOperators
        prepOperatorRegistration(false)
    {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        bytes memory signature;

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        signature = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](1);
        signers[0] = operatorOneAlias;

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        Task memory newTask = Task({
            taskId: "newTaskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        assertTrue(serviceManager.hashTaskWithExpiry(newTask) != taskDigest);

        vm.expectRevert();
        serviceManager.validateSignatures(newTask, signers, signatures);
    }

    function testSignaturesCannotBeRearranged() public permissionedOperators prepOperatorRegistration(false) {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        vm.prank(operatorTwo);
        serviceManager.registerOperatorToAVS(operatorTwoAlias, operatorTwoSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        bytes memory signatureOne = abi.encodePacked(r, s, v);

        (v, r, s) = vm.sign(operatorTwoAliasPk, taskDigest);
        bytes memory signatureTwo = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](2);
        bytes[] memory signatures = new bytes[](2);

        if (operatorOneAlias < operatorTwoAlias) {
            signers[0] = operatorOneAlias;
            signers[1] = operatorTwoAlias;
            signatures[0] = signatureOne;
            signatures[1] = signatureTwo;
        } else {
            signers[0] = operatorTwoAlias;
            signers[1] = operatorOneAlias;
            signatures[0] = signatureTwo;
            signatures[1] = signatureOne;
        }

        bool result = serviceManager.validateSignatures(task, signers, signatures);
        assertTrue(result, "First execution should succeed");

        bytes memory tmpSig = signatures[0];
        signatures[0] = signatures[1];
        signatures[1] = tmpSig;

        address tmpAddr;
        signers[0] = signers[1];
        signers[1] = tmpAddr;

        vm.expectRevert();
        serviceManager.validateSignatures(task, signers, signatures);
    }

    function testSignaturesGreaterThanQuorumThresholdCannotBeRearranged()
        public
        permissionedOperators
        prepOperatorRegistration(false)
    {
        Task memory task = Task({
            taskId: "taskId",
            msgSender: address(this),
            target: address(this),
            value: 0,
            encodedSigAndArgs: "",
            policyID: "testPolicy",
            quorumThresholdCount: 1,
            expireByBlockNumber: block.number + 100
        });

        bytes32 taskDigest = serviceManager.hashTaskWithExpiry(task);

        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        vm.prank(operatorTwo);
        serviceManager.registerOperatorToAVS(operatorTwoAlias, operatorTwoSignature);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOneAliasPk, taskDigest);
        bytes memory signatureOne = abi.encodePacked(r, s, v);

        (v, r, s) = vm.sign(operatorTwoAliasPk, taskDigest);
        bytes memory signatureTwo = abi.encodePacked(r, s, v);

        address[] memory signers = new address[](2);
        bytes[] memory signatures = new bytes[](2);

        if (operatorOneAlias < operatorTwoAlias) {
            signers[0] = operatorOneAlias;
            signers[1] = operatorTwoAlias;
            signatures[0] = signatureOne;
            signatures[1] = signatureTwo;
        } else {
            signers[0] = operatorTwoAlias;
            signers[1] = operatorOneAlias;
            signatures[0] = signatureTwo;
            signatures[1] = signatureOne;
        }

        serviceManager.validateSignatures(task, signers, signatures);

        bytes memory tmpSig = signatures[0];
        signatures[0] = signatures[1];
        signatures[1] = tmpSig;

        address tmpAddr;
        signers[0] = signers[1];
        signers[1] = tmpAddr;

        vm.expectRevert();
        serviceManager.validateSignatures(task, signers, signatures);
    }

    function testOperatorCannotRegisterWithOtherOperatorAlias()
        public
        permissionedOperators
        prepOperatorRegistration(false)
    {
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint256 stake, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(
            uint256(status), uint256(ServiceManager.OperatorStatus.REGISTERED), "Operator one should be registered"
        );

        vm.prank(operatorTwo);
        vm.expectRevert("ServiceManager.registerOperatorToAVS: operator already registered");
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorTwoSignature);

        (stake, status) = serviceManager.operators(operatorTwo);
        assertEq(
            uint256(status),
            uint256(ServiceManager.OperatorStatus.NEVER_REGISTERED),
            "Operator two should not be registered"
        );

        address registeredOperator = serviceManager.signingKeyToOperator(operatorOneAlias);
        assertEq(registeredOperator, operatorOne, "OperatorOneAlias should still be associated with operatorOne");
    }

    function testPermissionedOperatorCanRegister() public permissionedOperators prepOperatorRegistration(false) {
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);

        (uint256 stake, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(
            uint256(status), uint256(ServiceManager.OperatorStatus.REGISTERED), "Operator one should be registered"
        );
    }

    function testNonPermissionedOperatorCannotRegister() public prepOperatorRegistration(false) {
        vm.expectRevert();
        vm.prank(operatorOne);
        serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);
    }

    fallback() external payable {}

    receive() external payable {}
}
