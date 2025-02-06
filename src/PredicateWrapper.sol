// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {PaxosV4Hook} from "./PaxosV4Hook.sol";

import { PredicateClient } from "lib/predicate-std/src/mixins/PredicateClient.sol";
import { PredicateMessage } from "lib/predicate-std/src/interfaces/IPredicateClient.sol";

contract PredicateWrapper is PredicateClient {
    PaxosV4Hook public paxosV4Hook;

    constructor(address _serviceManager, string memory _policyID, address _paxosV4Hook) {
        _initPredicateClient(_serviceManager, _policyID);
        paxosV4Hook = PaxosV4Hook(_paxosV4Hook);
    }

    function beforeSwap(
            address sender,
            PoolKey calldata key, 
            IPoolManager.SwapParams calldata params, 
            bytes calldata hookData
        ) external returns (bytes4, BeforeSwapDelta, uint24) {
            (
                PredicateMessage memory predicateMessage,
                address msgSender,
                uint256 value
            ) = abi.decode(hookData, (PredicateMessage, address, uint256));

            bytes memory encodeSigAndArgs = abi.encodeWithSignature(
                "_beforeSwap(address,PoolKey,IPoolManager.SwapParams,bytes)",
                sender,
                key,
                params,
                hookData
            );

            require(
                _authorizeTransaction(
                    predicateMessage,
                    encodeSigAndArgs,
                    msgSender,
                    value
                ),
                "Unauthorized transaction"
            );

            (bytes4 selector, BeforeSwapDelta swapDelta, uint24 fee) = 
                  paxosV4Hook.beforeSwap(sender, 
                                                 key, 
                                                 params, 
                                                 hookData
            );
            return (selector, swapDelta, fee);
    }

    function setPolicy(string memory _policyID) external {
        _setPolicy(_policyID);
    }

    function setPredicateManager(address _predicateManager) public {
        _setPredicateManager(_predicateManager);
    }
    
    function setPaxosV4Hook(address _paxosV4Hook) external {
        paxosV4Hook = PaxosV4Hook(_paxosV4Hook);
    }
}