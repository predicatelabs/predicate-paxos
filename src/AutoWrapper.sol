// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTokenWrapperHook } from "v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import { wYBSV1 } from "./paxos/wYBSV1.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is BaseTokenWrapperHook {
    wYBSV1 public immutable wYBS;
    IERC20Upgradeable public immutable ybs;
    PoolKey public immutable wrappedPoolKey;

    constructor(
        IPoolManager _manager,
        address _wYBS,
        address _ybs, 
        PoolKey memory _poolKey
    ) BaseTokenWrapperHook(_manager, Currency.wrap(_wYBS), Currency.wrap(_ybs)) {
        wYBS = wYBSV1(wYBS);
        ybs = IERC20Upgradeable(_ybs);
        wrappedPoolKey = _poolKey;
    }

    /// @notice Handles token wrapping and unwrapping during swaps
    /// @dev Processes both exact input (amountSpecified < 0) and exact output (amountSpecified > 0) swaps
    /// @param params The swap parameters including direction and amount
    /// @return selector The function selector
    /// @return swapDelta The input/output token amounts for pool accounting
    /// @return lpFeeOverride The fee override (always 0 for wrapper pools)
    function _beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride)
    {
        bool isExactInput = params.amountSpecified < 0;

        if (wrapZeroForOne == params.zeroForOne) {
            // we are wrapping  => USDC -> USDL
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            _take(underlyingCurrency, address(this), inputAmount);
            uint256 wrappedAmount = _deposit(inputAmount);
            _settle(wrapperCurrency, address(this), wrappedAmount);
            int128 amountUnspecified =
                isExactInput ? -wrappedAmount.toInt256().toInt128() : inputAmount.toInt256().toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        } else {
            // we are unwrapping => USDL -> USDC
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnwrapInputRequired(uint256(params.amountSpecified));
            _take(wrapperCurrency, address(this), inputAmount);
            uint256 unwrappedAmount = _withdraw(inputAmount);
            _settle(underlyingCurrency, address(this), unwrappedAmount);
            int128 amountUnspecified =
                isExactInput ? -unwrappedAmount.toInt256().toInt128() : inputAmount.toInt256().toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        }

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    function _deposit(
        uint256 underlyingAmount
    ) internal override returns (uint256 wrapperAmount) {
        ybs.approve(address(wYBS), underlyingAmount);
        wYBS.deposit(underlyingAmount, address(this));
        return underlyingAmount;
    }

    function _withdraw(
        uint256 wrapperAmount
    ) internal override returns (uint256 underlyingAmount) {
        wYBS.redeem(wrapperAmount, address(this), address(this));
        return wrapperAmount;
    }
}
