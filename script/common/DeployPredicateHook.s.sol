// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";

import {PredicateHook} from "../../src/PredicateHook.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

contract DeployPredicateHook is Script {
    INetwork private _env;
    V4Router private _swapRouter;
    string private _policyId;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool swapRouterExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        bool policyIdExists = vm.envExists("POLICY_ID");
        require(
            networkExists && swapRouterExists && policyIdExists,
            "All environment variables must be set if any are specified"
        );
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        _swapRouter = V4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));
        _policyId = vm.envString("POLICY_ID");
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);

        bytes memory constructorArgs =
            abi.encode(config.poolManager, _swapRouter, config.serviceManager, _policyId, msg.sender);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(config.create2Deployer, flags, type(PredicateHook).creationCode, constructorArgs);
        console.log("Deploying PredicateHook at address: ", hookAddress);
        vm.startBroadcast();
        PredicateHook predicateHook =
            new PredicateHook{salt: salt}(config.poolManager, _swapRouter, config.serviceManager, _policyId, msg.sender);
        require(address(predicateHook) == hookAddress, "PredicateHook address does not match expected address");
        console.log("PredicateHook deployed at: ", address(predicateHook));
        vm.stopBroadcast();
    }
}
