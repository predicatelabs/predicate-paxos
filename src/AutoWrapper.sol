// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {wYBSV1} from "./paxos/wYBSV1.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is BaseHook {
    using SafeCast for uint256;
    using SafeCast for int256;

    Currency public immutable underlyingCurrency;
    Currency public immutable wrapperCurrency;
    wYBSV1 public immutable wYBS;
    IERC20Upgradeable public immutable ybs;
    PoolKey public underlyingPoolKey;
    bool public immutable shouldWrap;

    bytes4 constant BEFORE_SWAP_SELECTOR = IHooks.beforeSwap.selector;
    uint24 private constant DEFAULT_LP_FEE = 0;

    constructor(IPoolManager _manager, address _ybsAddress, PoolKey memory _poolKey) BaseHook(_manager) {
        wrapperCurrency = Currency.wrap(_ybsAddress);
        underlyingCurrency = _poolKey.currency0;
        wYBS = wYBSV1(Currency.unwrap(_poolKey.currency1));
        ybs = IERC20Upgradeable(_ybsAddress);
        shouldWrap = Currency.unwrap(underlyingCurrency) == _ybsAddress;
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
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        bool isExactInput = params.amountSpecified < 0;

        if (shouldWrap == params.zeroForOne) {
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            _take(underlyingCurrency, address(this), inputAmount);
            uint256 wrappedAmount = _deposit(inputAmount);
            _settle();
            int128 amountUnspecified =
                isExactInput ? -SafeCast.toInt128(int256(wrappedAmount)) : SafeCast.toInt128(int256(inputAmount));
            swapDelta = toBeforeSwapDelta(int128(-params.amountSpecified), amountUnspecified);
        } else {
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnwrapInputRequired(uint256(params.amountSpecified));
            _take(wrapperCurrency, address(this), inputAmount);
            uint256 unwrappedAmount = _withdraw(inputAmount);
            _settle();
            int128 amountUnspecified =
                isExactInput ? -SafeCast.toInt128(int256(unwrappedAmount)) : SafeCast.toInt128(int256(inputAmount));
            swapDelta = toBeforeSwapDelta(int128(-params.amountSpecified), amountUnspecified);
        }

        return (BEFORE_SWAP_SELECTOR, swapDelta, DEFAULT_LP_FEE);
    }

    function _deposit(
        uint256 underlyingAmount
    ) internal returns (uint256 wrapperAmount) {
        if (ybs.allowance(address(this), address(wYBS)) < underlyingAmount) {
            ybs.approve(address(wYBS), type(uint256).max);
        }
        wYBS.deposit(underlyingAmount, address(this));
        return underlyingAmount;
    }

    function _withdraw(
        uint256 wrapperAmount
    ) internal returns (uint256 underlyingAmount) {
        wYBS.redeem(wrapperAmount, address(this), address(this));
        return wrapperAmount;
    }

    function _take(Currency currency, address to, uint256 amount) internal {
        poolManager.take(currency, to, amount);
    }

    function _settle() internal {
        poolManager.settle();
    }

    function _getWrapInputRequired(
        uint256 outputAmount
    ) internal pure returns (uint256) {
        return outputAmount;
    }

    function _getUnwrapInputRequired(
        uint256 outputAmount
    ) internal pure returns (uint256) {
        return outputAmount;
    }
}
