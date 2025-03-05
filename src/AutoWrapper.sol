// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTokenWrapperHook} from "@uniswap/v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {wYBSV1} from "./paxos/wYBSV1.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is BaseTokenWrapperHook {
    wYBSV1 public immutable wYBS;
    IERC20Upgradeable public immutable ybs;

    constructor(
        IPoolManager _manager,
        wYBSV1 _wYBS
    ) BaseTokenWrapperHook(_manager, Currency.wrap(address(_wYBS)), Currency.wrap(address(_wYBS.asset()))) {
        wYBS = _wYBS;
        ybs = IERC20Upgradeable(_wYBS.asset());
        ERC20(Currency.unwrap(underlyingCurrency)).approve(address(wYBS), type(uint256).max);
    }

    function _deposit(
        uint256 underlyingAmount
    ) internal override returns (uint256) {
        return wYBS.deposit(underlyingAmount, address(this));
    }

    function _withdraw(
        uint256 wrapperAmount
    ) internal override returns (uint256) {
        return wYBS.redeem(wrapperAmount, address(this), address(this));
    }

    function _getWrapInputRequired(
        uint256 wrappedAmount
    ) internal view override returns (uint256) {
        return wYBS.previewMint(wrappedAmount);
    }

    function _getUnwrapInputRequired(
        uint256 underlyingAmount
    ) internal view override returns (uint256) {
        return wYBS.previewWithdraw(underlyingAmount);
    }
}
