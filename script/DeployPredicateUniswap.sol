// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { PredicateUniswap } from "../src/PredicateUniswap.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";

contract DeployPredicateUniswap is Script {
    address public poolManagerAddress;

    function setUp() public {
        poolManagerAddress = vm.envAddress("POOL_MANAGER");
        require(poolManagerAddress != address(0), "Invalid POOL_MANAGER address");
    }

    function run() public {
        vm.startBroadcast();

        PredicateUniswap predicateUniswap = new PredicateUniswap(IPoolManager(poolManagerAddress));
        console.log("PredicateUniswap deployed at:", address(predicateUniswap));
        console.log("PoolManager address:", poolManagerAddress);

        vm.stopBroadcast();
    }
}
