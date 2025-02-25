// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

abstract contract TokenWrapperHook is BaseHook {
    using SafeCast for uint256;
    using SafeCast for int256;

    Currency public immutable wrapperCurrency;
    Currency public immutable underlyingCurrency;

    constructor(
        IPoolManager _poolManager,
        Currency _wrapperCurrency,
        Currency _underlyingCurrency
    ) BaseHook(_poolManager) {
        wrapperCurrency = _wrapperCurrency;
        underlyingCurrency = _underlyingCurrency;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            beforeAddLiquidity: true,
            beforeSwap: true,
            beforeSwapReturnDelta: true,
            afterSwap: false,
            afterInitialize: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeDonate: false,
            afterDonate: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        bool isExactInput = params.amountSpecified < 0;

        int128 amountUnspecified = isExactInput 
            ? params.amountSpecified.toInt128()
            : params.amountSpecified.toInt128();

        swapDelta = toBeforeSwapDelta(
            params.amountSpecified.toInt128(),
            amountUnspecified
        );

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    function _deposit(uint256 underlyingAmount) internal virtual returns (uint256 wrapperAmount);
    function _withdraw(uint256 wrapperAmount) internal virtual returns (uint256 underlyingAmount);

    function _take(Currency currency, address to, uint256 amount) internal {
        poolManager.take(currency, to, amount);
    }

    function _settle(Currency currency, address to, uint256 amount) internal {
        poolManager.settle();
    }

    function _getWrapInputRequired(uint256 outputAmount) internal view returns (uint256) {
        return outputAmount;
    }

    function _getUnwrapInputRequired(uint256 outputAmount) internal view returns (uint256) {
        return outputAmount;
    }
}