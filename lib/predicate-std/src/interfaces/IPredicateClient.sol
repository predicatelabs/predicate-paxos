// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {IPredicateManager} from "../interfaces/IPredicateManager.sol";

// @notice Struct that bundles together a task's parameters for validation
struct PredicateMessage {
    // the unique identifier for the task
    string taskId;
    // the expiration block number for the task
    uint256 expireByBlockNumber;
    // the operators that have signed the task
    address[] signerAddresses;
    // the signatures of the operators that have signed the task
    bytes[] signatures;
}

// @notice Struct to contain stateful values for PredicateClient-type contracts
// @custom:storage-location erc7201:predicate.storage.PredicateClient
struct PredicateClientStorage {
    IPredicateManager serviceManager;
    string policyID;
}

// @notice error type for unauthorized access
error PredicateClient__Unauthorized();

// @notice Interface for a PredicateClient-type contract that enables clients to define execution rules or parameters for tasks they submit
interface IPredicateClient {
    /**
     * @notice Sets a policy for the calling address, associating it with a policy document stored on IPFS.
     * @param _policyID A string representing the policyID from on chain.
     * @dev This function enables clients to define execution rules or parameters for tasks they submit.
     *      The policy governs how tasks submitted by the caller are executed, ensuring compliance with predefined rules.
     */
    function setPolicy(
        string memory _policyID
    ) external;

    /**
     * @notice Retrieves the policy for the calling address.
     * @return The policyID associated with the calling address.
     */
    function getPolicy() external view returns (string memory);

    /**
     * @notice Function for setting the Predicate ServiceManager
     * @param _predicateManager address of the service manager
     */
    function setPredicateManager(
        address _predicateManager
    ) external;

    /**
     * @notice Function for getting the Predicate ServiceManager
     * @return address of the service manager
     */
    function getPredicateManager() external view returns (address);
}
