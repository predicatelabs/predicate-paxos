// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

contract MockAVSDirectory {
    mapping(address => mapping(address => OperatorAVSRegistrationStatus)) public avsOperatorStatus;

    enum OperatorAVSRegistrationStatus {
        UNREGISTERED, // Operator not registered to AVS
        REGISTERED // Operator registered to AVS

    }

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {
        // Set the operator as registered
        avsOperatorStatus[msg.sender][operator] = OperatorAVSRegistrationStatus.REGISTERED;
    }

    function deregisterOperatorFromAVS(
        address operator
    ) external {
        // Set the operator as deregistered
        avsOperatorStatus[msg.sender][operator] = OperatorAVSRegistrationStatus.UNREGISTERED;
    }

    function updateAVSMetadataURI(
        string calldata metadataURI
    ) external {}

    function calculateOperatorAVSRegistrationDigestHash(
        address operator,
        address avs,
        bytes32 salt,
        uint256 expiry
    ) public view returns (bytes32) {
        // calculate the struct hash
        // Mock Implementation only
        bytes32 structHash = keccak256(abi.encode(operator, avs, salt, expiry));
        return structHash;
    }
}
