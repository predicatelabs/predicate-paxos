// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTokenWrapperHook } from "v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import { wYBSV1 } from "./paxos/wYBSV1.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is BaseTokenWrapperHook {
    using PoolIdLibrary for PoolKey;

    wYBSV1 public immutable wYBS;
    IERC20Upgradeable public immutable ybs;

    error WithdrawFailed();

    constructor(
        IPoolManager _manager,
        address _wYBS,
        address _ybs
    ) BaseTokenWrapperHook(_manager, Currency.wrap(_wYBS), Currency.wrap(_ybs)) {
        wYBS = wYBSV1(payable(_wYBS));
        ybs = IERC20Upgradeable(_ybs);   
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
