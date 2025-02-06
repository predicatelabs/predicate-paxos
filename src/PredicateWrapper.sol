// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {PredicateUniswap} from "./PredicateUniswap.sol";

import { PredicateClient } from "lib/predicate-std/src/mixins/PredicateClient.sol";
import { PredicateMessage } from "lib/predicate-std/src/interfaces/IPredicateClient.sol";

contract PredicateWrapper is PredicateClient {
    constructor(address _serviceManager, string memory _policyID) {
        _initPredicateClient(_serviceManager, _policyID);
    }

    function beforeSwap(
            address sender,
            PoolKey calldata key, 
            IPoolManager.SwapParams calldata params, 
            bytes calldata hookData
        ) external override returns (bytes4, BeforeSwapDelta, uint24) {
            (
                PredicateMessage memory predicateMessage,
                address msgSender,
                uint256 amount0,
                uint256 amount1
            ) = abi.decode(hookData, (PredicateMessage, address, uint256, uint256));

            bytes memory encodeSigAndArgs = abi.encodeWithSignature(
                "_beforeSwap(address,PoolKey,IPoolManager.SwapParams,bytes)",
                sender,
                key,
                params,
                hookData
            );

            // require(
            //     _authorizeTransaction(
            //         predicateMessage,
            //         encodeSigAndArgs,
            //         msgSender,
            //         amount0,
            //         amount1
            //     ),
            //     "Unauthorized transaction"
            // );

            BeforeSwapDelta swapDelta = BeforeSwapDelta(0,0);
            return (this.beforeSwap.selector, swapDelta, 0);
    }

    function setPolicy(string memory _policyID) external {
        _setPolicy(_policyID);
    }

    function setPredicateManager(address _predicateManager) public {
        _setPredicateManager(_predicateManager);
    }
}