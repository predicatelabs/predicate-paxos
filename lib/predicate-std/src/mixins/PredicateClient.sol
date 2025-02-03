// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {IPredicateManager, Task} from "../interfaces/IPredicateManager.sol";
import "../interfaces/IPredicateClient.sol";

abstract contract PredicateClient is IPredicateClient {
    // @notice the storage slot for the PredicateClientStorage struct
    // @dev keccak256(abi.encode(uint256(keccak256("predicate.storage.PredicateClient")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PREDICATE_CLIENT_STORAGE_SLOT =
        0x804776a84f3d03ad8442127b1451e2fbbb6a715c681d6a83c9e9fca787b99300;

    // @notice retrieves the PredicateClientStorage struct from the configured storage slot
    function _getPredicateClientStorage() private pure returns (PredicateClientStorage storage $) {
        assembly {
            $.slot := _PREDICATE_CLIENT_STORAGE_SLOT
        }
    }

    /**
     * @notice Sets a policy and serviceManager for the predicate client.
     * @param _serviceManagerAddress Address of the associated PredicateManager contract.
     * @param _policyID A string representing the predicate policyID.
     * @dev This function enables clients to define execution rules or parameters for tasks they submit.
     *      The policy governs how tasks submitted by the caller are executed, ensuring compliance with predefined rules.
     */
    function _initPredicateClient(address _serviceManagerAddress, string memory _policyID) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.serviceManager = IPredicateManager(_serviceManagerAddress);
        $.policyID = _policyID;
    }

    // @notice internal function to set the policyID
    function _setPolicy(
        string memory _policyID
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.policyID = _policyID;
    }

    // @inheritdoc IPredicateClient
    function getPolicy() external view override returns (string memory) {
        return _getPolicy();
    }

    // @notice internal function to get the policyID from PredicateClientStorage
    function _getPolicy() internal view returns (string memory) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        return $.policyID;
    }

    // @notice internal function to set the Predicate ServiceManager
    function _setPredicateManager(
        address _predicateManager
    ) internal {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        $.serviceManager = IPredicateManager(_predicateManager);
    }

    // @inheritdoc IPredicateClient
    function getPredicateManager() external view override returns (address) {
        return _getPredicateManager();
    }

    // @notice internal function to get the Predicate ServiceManager address from PredicateClientStorage
    function _getPredicateManager() internal view returns (address) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        return address($.serviceManager);
    }

    /**
     * @notice Restricts access to the Predicate ServiceManager
     */
    modifier onlyPredicateServiceManager() {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        if (msg.sender != address($.serviceManager)) {
            revert PredicateClient__Unauthorized();
        }
        _;
    }

    function _authorizeTransaction(
        PredicateMessage memory _predicateMessage,
        bytes memory _encodedSigAndArgs,
        address _msgSender,
        uint256 _value
    ) internal returns (bool) {
        PredicateClientStorage storage $ = _getPredicateClientStorage();
        Task memory task = Task({
            msgSender: _msgSender,
            target: address(this),
            value: _value,
            encodedSigAndArgs: _encodedSigAndArgs,
            policyID: $.policyID,
            quorumThresholdCount: uint32(_predicateMessage.signerAddresses.length),
            taskId: _predicateMessage.taskId,
            expireByBlockNumber: _predicateMessage.expireByBlockNumber
        });

        return
            $.serviceManager.validateSignatures(task, _predicateMessage.signerAddresses, _predicateMessage.signatures);
    }
}
