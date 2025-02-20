// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {PaxosHook} from "./PaxosHook.sol";

import { PredicateClient } from "lib/predicate-std/src/mixins/PredicateClient.sol";
import { PredicateMessage } from "lib/predicate-std/src/interfaces/IPredicateClient.sol";

/// @title Predicate Hook
/// @author Predicate Labs
/// @notice A hook for compliant swaps
contract PredicateHook is BaseHook, PredicateClient {
    constructor(IPoolManager _poolManager, address _serviceManager, string memory _policyID) BaseHook(_poolManager) {
        _initPredicateClient(_serviceManager, _policyID);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
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
                uint256 msgValue
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
                    msgValue
                ),
                "Unauthorized transaction"
            );

            (bytes4 selector, BeforeSwapDelta swapDelta, uint24 fee) = 
                  paxosHook.beforeSwap(sender, 
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
    
    function setPaxosHook(address _paxosHook) external {
        paxosHook = PaxosHook(_paxosHook);
    }
}