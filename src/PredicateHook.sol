// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title Predicated Hook
/// @author Predicate Labs
/// @notice A hook for compliant swaps
contract PredicateHook is BaseHook, PredicateClient {
    ISimpleV4Router public immutable router;

    constructor(
        IPoolManager _poolManager,
        ISimpleV4Router _router,
        address _serviceManager,
        string memory _policyID
    ) BaseHook(_poolManager) {
        _initPredicateClient(_serviceManager, _policyID);
        router = _router;
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

    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) = this.decodeHookData(hookData);

        bytes memory encodeSigAndArgs = abi.encodeWithSignature(
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)",
            router.msgSender(),
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            address(key.hooks),
            params.zeroForOne,
            params.amountSpecified,
            params.sqrtPriceLimitX96
        );

        require(
            _authorizeTransaction(predicateMessage, encodeSigAndArgs, msgSender, msgValue), "Unauthorized transaction"
        );

        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0);

        return (IHooks.beforeSwap.selector, delta, 100);
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

    function decodeHookData(
        bytes calldata hookData
    ) external pure returns (PredicateMessage memory, address, uint256) {
        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) =
            abi.decode(hookData, (PredicateMessage, address, uint256));

        return (predicateMessage, msgSender, msgValue);
    }
}
