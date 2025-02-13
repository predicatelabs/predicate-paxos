// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTokenWrapperHook} from "v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import {wYBSV1} from "lib/ybs-contract/contracts/wYBSV1.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title Paxos Hook
/// @author Predicate
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract PaxosHook is BaseTokenWrapperHook {
    using PoolIdLibrary for PoolKey;

    wYBSV1 public immutable wYBS;

    error WithdrawFailed();

    constructor(IPoolManager _manager, address _wYBS, address _ybs)
        BaseTokenWrapperHook(
            _manager,
            Currency.wrap(_wYBS), 
            Currency.wrap(_ybs)
        )
    {
        wYBS = wYBSV1(payable(_wYBS));
    }

    function deposit(uint256 underlyingAmount) internal override returns (uint256 wrapperAmount) {
        IERC20Upgradeable(ybsAddress).approve(address(wYBS), underlyingAmount);
        wYBS.deposit(underlyingAmount, address(this));
        return underlyingAmount; 
    }

    function withdraw(uint256 wrapperAmount) internal override returns (uint256 underlyingAmount) {
        wYBS.redeem(wrapperAmount, address(this), address(this));
        return wrapperAmount; 
    }
}