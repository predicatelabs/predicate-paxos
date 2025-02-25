// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { CustomTokenWrapperHook } from "./base/CustomTokenWrapperHook.sol";
import { wYBSV1 } from "./paxos/wYBSV1.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is CustomTokenWrapperHook {
    using CurrencyLibrary for Currency;
    using SafeCast for int256;
    using SafeCast for uint256;

    wYBSV1 _wYBS;
    IERC20Upgradeable _ybs;
    IERC20 _usdc;
    PoolKey _underlyingPoolKey;

    constructor(
        IPoolManager _manager,
        address _ybsAddress, // USDL
        PoolKey memory _poolKey // token0 is USDC, token1 is wUSDL
    ) CustomTokenWrapperHook(_manager, _poolKey.currency1, Currency.wrap(_ybsAddress)) { 
        _usdc = IERC20(Currency.unwrap(_poolKey.currency0));
        _wYBS = wYBSV1(Currency.unwrap(_poolKey.currency1));
        _ybs = IERC20Upgradeable(_ybsAddress);
        _underlyingPoolKey = _poolKey;
    }

    function _beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride)
    {
        bool isExactInput = params.amountSpecified < 0;
        bool wrapZeroForOne = params.zeroForOne;

        if (wrapZeroForOne == params.zeroForOne) {
            // we are wrapping  => USDC -> USDL   USDC/USDL
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));

            // transfer USDC to this contract
            // swap
            // transfer USDL to this contract
            // settle
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
            
            // transfer USDL to the ERC4626 contract
            // get wUSDL and swap
            // transfer USDC to the user
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
        _ybs.approve(address(_wYBS), underlyingAmount);
        _wYBS.deposit(underlyingAmount, address(this));
        return underlyingAmount;
    }

    function _withdraw(
        uint256 wrapperAmount
    ) internal override returns (uint256 underlyingAmount) {
        _wYBS.redeem(wrapperAmount, address(this), address(this));
        return wrapperAmount;
    }
}
