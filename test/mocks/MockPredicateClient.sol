// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PredicateMessage} from "lib/predicate-std/src/interfaces/IPredicateClient.sol";

/// @notice A mock contract or utility to help with _authorizeTransaction.
contract MockPredicateClient {
    bool public authorized = true;

    function _authorizeTransaction(
        PredicateMessage memory,
        bytes memory,
        address,
        uint256
    ) internal view returns (bool) {
        return authorized;
    }

    function setAuthorized(bool _authorized) external {
        authorized = _authorized;
    }
}