// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {SignatureWithSaltAndExpiry} from "../../../src/interfaces/IPredicateManager.sol";
import "./TestStorage.sol";

contract TestPrep is TestStorage {
    modifier prepOperatorRegistration(
        bool avsVerified
    ) {
        vm.startPrank(operatorOne);
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: operatorAddr,
            delegationApprover: operatorAddr,
            stakerOptOutWindowBlocks: 0
        });

        bytes32 messageHash = delegationManager.calculateOperatorAVSRegistrationDigestHash(
            operatorOne, address(serviceManager), keccak256("abc"), 10_000_000_000_000
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorOnePk, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        operatorSignature =
            SignatureWithSaltAndExpiry({signature: signature, salt: keccak256("abc"), expiry: 10_000_000_000_000});
        delegationManager.registerAsOperator(operatorDetails, "metadata uri");

        (, ServiceManager.OperatorStatus status) = serviceManager.operators(operatorOne);
        assertEq(uint256(status), 0);
        if (avsVerified) {
            serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);
        }
        vm.stopPrank();

        vm.startPrank(operatorTwo);
        IDelegationManager.OperatorDetails memory operatorTwoDetails = IDelegationManager.OperatorDetails({
            earningsReceiver: operatorTwoAddr,
            delegationApprover: operatorTwoAddr,
            stakerOptOutWindowBlocks: 0
        });

        bytes32 messageHashTwo = delegationManager.calculateOperatorAVSRegistrationDigestHash(
            operatorTwo, address(serviceManager), keccak256("abc"), 10_000_000_000_000
        );

        (v, r, s) = vm.sign(operatorTwoPk, messageHashTwo);
        signature = abi.encodePacked(r, s, v);

        operatorTwoSignature =
            SignatureWithSaltAndExpiry({signature: signature, salt: keccak256("abc"), expiry: 10_000_000_000_000});

        delegationManager.registerAsOperator(operatorTwoDetails, "metadata uri");
        (, status) = serviceManager.operators(operatorTwo);
        assertEq(uint256(status), 0);
        if (avsVerified) {
            vm.prank(operatorOne);
            serviceManager.registerOperatorToAVS(operatorOneAlias, operatorSignature);
        }
        vm.stopPrank();

        _;
    }
}
