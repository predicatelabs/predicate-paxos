// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PaxosV4Hook} from "../../src/PaxosV4Hook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";


contract MockPaxosV4Hook is PaxosV4Hook {
    constructor(IPoolManager _poolManager) PaxosV4Hook(_poolManager) {}

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    )
        external
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (bytes4(keccak256("MockBeforeSwap()")), BeforeSwapDeltaLibrary.ZERO_DELTA, 300);
    }
}