// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";
import {Lock} from "./base/Lock.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/**
 * @title SimpleV4Router
 * @notice A simple V4 router that allows users to swap between two currencies
 * @dev This router is used to swap between two currencies in the Uniswap V4 protocol
 */
contract SimpleV4Router is ISimpleV4Router, SafeCallback, Lock, DeltaResolver {
    using TransientStateLibrary for IPoolManager;

    /**
     * @notice Constructor for the SimpleV4Router
     * @param _poolManager The Uniswap V4 pool manager
     */
    constructor(
        IPoolManager _poolManager
    ) SafeCallback(_poolManager) {}

    /**
     * @notice Swaps between two currencies
     * @param key The pool key
     * @param params The swap parameters
     * @param hookData The hook data
     * @return delta The balance delta
     */
    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes memory hookData
    ) external payable isNotLocked returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.unlock(abi.encode(ISimpleV4Router.CallbackData(msg.sender, key, params, hookData))),
            (BalanceDelta)
        );
    }

    /**
     * @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
     * times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
     * @return The address of the initiator of the lock
     */
    function msgSender() public view override returns (address) {
        return _getLocker();
    }

    /**
     * @notice Implementation of DeltaResolver's payment method
     * @dev Transfers tokens to the pool manager to settle negative deltas
     * @param token The token to transfer
     * @param amount The amount to transfer
     */
    function _pay(Currency token, address sender, uint256 amount) internal override {
        IERC20(Currency.unwrap(token)).transferFrom(sender, address(poolManager), amount);
    }

    /**
     * @notice Internal function to handle the callback from the pool manager
     * @param rawData The raw data from the pool manager
     * @return The encoded balance delta
     */
    function _unlockCallback(
        bytes calldata rawData
    ) internal override returns (bytes memory) {
        ISimpleV4Router.CallbackData memory data = abi.decode(rawData, (ISimpleV4Router.CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);
        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        // settle the delta for the currency0 and currency1
        if (delta0 < 0) {
            _settle(data.key.currency0, data.sender, uint256(-delta0));
        }
        if (delta1 < 0) {
            _settle(data.key.currency1, data.sender, uint256(-delta1));
        }
        if (delta0 > 0) {
            _take(data.key.currency0, data.sender, uint256(delta0));
        }
        if (delta1 > 0) {
            _take(data.key.currency1, data.sender, uint256(delta1));
        }

        return abi.encode(delta);
    }
}
