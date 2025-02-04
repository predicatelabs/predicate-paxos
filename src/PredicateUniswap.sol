// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPoolManager } from "lib/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "lib/v4-core/src/types/PoolKey.sol";

contract PredicateUniswap {
    IPoolManager public immutable poolManager;

    event PoolCreated(address indexed token0, address indexed token1, uint24 fee, address pool);

    constructor(
        IPoolManager _poolManager
    ) {
        require(address(_poolManager) != address(0), "Invalid PoolManager address");
        poolManager = _poolManager;
    }

    function createV4Pool(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) public returns (int24 tick) {
        require(token0 != address(0) && token1 != address(0), "Invalid token address");
        require(fee > 0, "Fee must be positive");
        require(sqrtPriceX96 > 0, "Invalid sqrtPriceX96");

        PoolKey memory tempKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });

        tick = poolManager.initalize(poolKey, sqrtPriceX96);
    
        emit PoolCreated(token0, token1, fee, pool);
    }
}
