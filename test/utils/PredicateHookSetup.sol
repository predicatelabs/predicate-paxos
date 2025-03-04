// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {STMSetup} from "@predicate-test/helpers/utility/STMSetup.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {PoolSetup} from "./PoolSetup.sol";

contract PredicateHookSetup is STMSetup, PoolSetup {
    PredicateHook public hook;
    address public sender;

    function setUpPoolAndHook() internal {
        sender = makeAddr("sender");
        deployPoolManager();
        deployRouters();
        deployPosm();
        deployAndMintTokens(sender);

        serviceManager.deployPolicy("x-aleo-6a52de9724a6e8f2", "test-policy", 1);

        // create hook here
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(manager, swapRouter, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{salt: salt}(manager, swapRouter, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        require(address(hook) == hookAddress, "Hook deployment failed");

        vm.startPrank(sender);
        initPoolAndSetApprovals(hook);
        vm.stopPrank();
    }
}
