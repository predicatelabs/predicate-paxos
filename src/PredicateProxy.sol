// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {PaxosHook} from "./PaxosHook.sol";

import {PredicateClient} from "lib/predicate-std/src/mixins/PredicateClient.sol";
import {PredicateMessage} from "lib/predicate-std/src/interfaces/IPredicateClient.sol";

/// @title Predicate Hook
/// @author Predicate
/// @notice A hook for compliant swaps
contract PredicateProxy is PredicateClient {
    PaxosHook public paxosHook;

    constructor(address _serviceManager, string memory _policyID, address _paxosHook) {
        require(_paxosHook != address(0), "Hook address cannot be zero");

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_paxosHook)
        }
        require(codeSize > 0, "Invalid hook address");

        _initPredicateClient(_serviceManager, _policyID);
        paxosHook = PaxosHook(_paxosHook);
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) =
            abi.decode(hookData, (PredicateMessage, address, uint256));

        bytes memory encodeSigAndArgs = abi.encodeWithSignature(
            "_beforeSwap(address,PoolKey,IPoolManager.SwapParams,bytes)", sender, key, params, hookData
        );

        require(
            _authorizeTransaction(predicateMessage, encodeSigAndArgs, msgSender, msgValue), "Unauthorized transaction"
        );

        (bytes4 selector, BeforeSwapDelta swapDelta, uint24 fee) = paxosHook.beforeSwap(sender, key, params, hookData);
        return (selector, swapDelta, fee);
    }

    function setPolicy(
        string memory _policyID
    ) external {
        _setPolicy(_policyID);
    }

    function setPredicateManager(
        address _predicateManager
    ) public {
        _setPredicateManager(_predicateManager);
    }

    function setPaxosHook(
        address _paxosHook
    ) external {
        paxosHook = PaxosHook(_paxosHook);
    }
}
