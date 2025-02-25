// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TokenWrapperHook} from "./base/TokenWrapperHook.sol";
import {wYBSV1} from "./paxos/wYBSV1.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is TokenWrapperHook {
    wYBSV1 public immutable wYBS;
    IERC20Upgradeable public immutable ybs;
    PoolKey public underlyingPoolKey;
    IERC20 public immutable usdc;
    bool public immutable wrapZeroForOne;

    constructor(
        IPoolManager _manager,
        address _ybsAddress,
        PoolKey memory _poolKey
    ) TokenWrapperHook(_manager, _poolKey.currency1, Currency.wrap(_ybsAddress)) {
        usdc = IERC20(Currency.unwrap(_poolKey.currency0));
        wYBS = wYBSV1(Currency.unwrap(_poolKey.currency1));
        ybs = IERC20Upgradeable(_ybsAddress);
        underlyingPoolKey = _poolKey;
        wrapZeroForOne = Currency.unwrap(_poolKey.currency0) == _ybsAddress;
    }

    function _beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        bool isExactInput = params.amountSpecified < 0;

        if (wrapZeroForOne == params.zeroForOne) {
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            _take(underlyingCurrency, address(this), inputAmount);
            uint256 wrappedAmount = _deposit(inputAmount);
            _settle(wrapperCurrency, address(this), wrappedAmount);
            int128 amountUnspecified = isExactInput ? -int128(int256(wrappedAmount)) : int128(int256(inputAmount));
            swapDelta = toBeforeSwapDelta(int128(-params.amountSpecified), amountUnspecified);
        } else {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnwrapInputRequired(uint256(params.amountSpecified));
            _take(wrapperCurrency, address(this), inputAmount);
            uint256 unwrappedAmount = _withdraw(inputAmount);
            _settle(underlyingCurrency, address(this), unwrappedAmount);
            int128 amountUnspecified = isExactInput ? -int128(int256(unwrappedAmount)) : int128(int256(inputAmount));
            swapDelta = toBeforeSwapDelta(int128(-params.amountSpecified), amountUnspecified);
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
