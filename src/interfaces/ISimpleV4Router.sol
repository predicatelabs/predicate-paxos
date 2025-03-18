// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/**
 * @title ISimpleV4Router
 * @notice A simple V4 router that allows users to swap between two currencies
 * @dev This router is used to swap between two currencies in the Uniswap V4 protocol
 */
interface ISimpleV4Router {
    /**
     * @notice A struct that contains the data for the callback
     * @param sender The address of the sender
     * @param key The pool key
     * @param params The swap parameters
     * @param hookData The hook data
     */
    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    /// @notice function that executes a swap
    /// @param key the pool key
    /// @param params the swap parameters
    /// @param hookData the hook data
    /// @return delta the balance delta
    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta);

    /// @notice function that returns address considered executor of the actions
    /// @dev The other context functions, _msgData and _msgValue, are not supported by this contract
    /// `msg.sender` shouldn't be used, as this will be the v4 pool manager contract that calls `unlockCallback`
    /// this is the address that calls the initial entry point for the actions
    function msgSender() external returns (address);
}
