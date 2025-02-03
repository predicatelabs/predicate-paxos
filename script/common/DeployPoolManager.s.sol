// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

contract DeployPoolManager is Script {
    function run() public {
        vm.startBroadcast();
        IPoolManager poolManager = IPoolManager(new PoolManager(address(0)));
        console.log("Deployed PoolManager at address: ", address(poolManager));
        vm.stopBroadcast();
    }
}
