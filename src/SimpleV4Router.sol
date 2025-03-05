// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";
import {Lock} from "./base/Lock.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

contract SimpleV4Router is ISimpleV4Router, SafeCallback, Lock {
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    constructor(
        IPoolManager _poolManager
    ) SafeCallback(_poolManager) {}

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

    /// @notice Public view function to be used instead of msg.sender, as the contract performs self-reentrancy and at
    /// times msg.sender == address(this). Instead msgSender() returns the initiator of the lock
    function msgSender() public view override returns (address) {
        return _getLocker();
    }

    function _unlockCallback(
        bytes calldata rawData
    ) internal override returns (bytes memory) {
        ISimpleV4Router.CallbackData memory data = abi.decode(rawData, (ISimpleV4Router.CallbackData));

        (,, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender, address(this));
        require(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);

        // TODO: use DeltaResolver and Permit2Payments to settle balances
        (,, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                require(
                    deltaAfter0 >= data.params.amountSpecified,
                    "deltaAfter0 is not greater than or equal to data.params.amountSpecified"
                );
                require(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                require(deltaAfter1 >= 0, "deltaAfter1 is not greater than or equal to 0");
            } else {
                // exact output, 0 for 1
                require(deltaAfter0 <= 0, "deltaAfter0 is not less than or equal to zero");
                require(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
                require(
                    deltaAfter1 <= data.params.amountSpecified,
                    "deltaAfter1 is not less than or equal to data.params.amountSpecified"
                );
            }
        } else {
            if (data.params.amountSpecified < 0) {
                // exact input, 1 for 0
                require(
                    deltaAfter1 >= data.params.amountSpecified,
                    "deltaAfter1 is not greater than or equal to data.params.amountSpecified"
                );
                require(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
                require(deltaAfter0 >= 0, "deltaAfter0 is not greater than or equal to 0");
            } else {
                // exact output, 1 for 0
                require(deltaAfter1 <= 0, "deltaAfter1 is not less than or equal to 0");
                require(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                require(
                    deltaAfter0 <= data.params.amountSpecified,
                    "deltaAfter0 is not less than or equal to data.params.amountSpecified"
                );
            }
        }

        if (deltaAfter0 < 0) {
            data.key.currency0.settle(poolManager, data.sender, uint256(-deltaAfter0), false);
        }
        if (deltaAfter1 < 0) {
            data.key.currency1.settle(poolManager, data.sender, uint256(-deltaAfter1), false);
        }
        if (deltaAfter0 > 0) {
            data.key.currency0.take(poolManager, data.sender, uint256(deltaAfter0), false);
        }
        if (deltaAfter1 > 0) {
            data.key.currency1.take(poolManager, data.sender, uint256(deltaAfter1), false);
        }

        return abi.encode(delta);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    ) internal view returns (uint256 userBalance, uint256 poolBalance, int256 delta) {
        userBalance = CurrencyLibrary.balanceOf(currency, user);
        poolBalance = CurrencyLibrary.balanceOf(currency, address(poolManager));
        delta = poolManager.currencyDelta(deltaHolder, currency);
    }
}
