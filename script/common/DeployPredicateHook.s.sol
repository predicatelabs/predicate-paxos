// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {PredicateHook} from "../../src/PredicateHook.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

contract DeployPredicateHook is Script {
    INetwork private _env;
    ISimpleV4Router private swapRouter;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool swapRouterExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        require(networkExists && swapRouterExists, "All environment variables must be set if any are specified");
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        swapRouter = ISimpleV4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);

        bytes memory constructorArgs =
            abi.encode(config.poolManager, swapRouter, config.serviceManager, config.policyId, msg.sender);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(config.create2Deployer, flags, type(PredicateHook).creationCode, constructorArgs);
        console.log("Deploying PredicateHook at address: ", hookAddress);
        vm.startBroadcast();
        PredicateHook predicateHook = new PredicateHook{salt: salt}(
            config.poolManager, swapRouter, config.serviceManager, config.policyId, msg.sender
        );
        require(address(predicateHook) == hookAddress, "PredicateHook address does not match expected address");
        console.log("PredicateHook deployed at: ", address(predicateHook));
        vm.stopBroadcast();
    }
}
