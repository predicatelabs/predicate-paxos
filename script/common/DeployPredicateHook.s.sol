// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";

import {PredicateHook} from "../../src/PredicateHook.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

contract DeployPredicateHook is Script {
    INetwork private _env;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        if (networkExists) {
            require(networkExists, "All environment variables must be set if any are specified");
            string memory _network = vm.envString("NETWORK");
            _env = new NetworkSelector().select(_network);
        } else {
            _env = new NetworkSelector().select("LOCAL");
            console.log("No network specified. Defaulting to LOCAL.");
        }
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        bytes memory constructorArgs =
            abi.encode(config.poolManager, config.router, config.serviceManager, config.policyId);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(config.create2Deployer, flags, type(PredicateHook).creationCode, constructorArgs);
        console.log("Deploying PredicateHook at address: ", hookAddress);
        vm.startBroadcast();
        PredicateHook predicateHook =
            new PredicateHook{salt: salt}(config.poolManager, config.router, config.serviceManager, config.policyId);
        require(address(predicateHook) == hookAddress, "PredicateHook address does not match expected address");
        console.log("PredicateHook deployed at: ", address(predicateHook));
        vm.stopBroadcast();
    }
}
