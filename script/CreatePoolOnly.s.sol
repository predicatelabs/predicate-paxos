// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

import {Constants} from "./base/Constants.sol";
import {Config} from "./base/Config.sol";

contract CreatePoolOnly is Script, Constants, Config {
    using CurrencyLibrary for Currency;

    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;

    uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

    uint256 public token0Amount = 1e18;
    uint256 public token1Amount = 1e18;

    int24 tickLower = -600; 
    int24 tickUpper = 600;

    function run() external {
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });
        bytes memory hookData = new bytes(0);

        vm.broadcast();
        IPoolManager(POOLMANAGER).initialize(pool, startingPrice);
    }
}