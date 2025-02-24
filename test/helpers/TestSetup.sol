// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import { PredicateHook } from "../../src/PredicateHook.sol";
import { SimpleV4Router } from "../../src/SimpleV4Router.sol";
import { ISimpleV4Router } from "../../src/interfaces/ISimpleV4Router.sol";

import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { STMSetup } from "@predicate-test/helpers/utility/STMSetup.sol";
import { HookMiner } from "test/utils/HookMiner.sol";

contract TestSetup is STMSetup {
    PredicateHook public hook;
    IPoolManager public poolManager;
    ISimpleV4Router public router;

    function setUpHook() internal {
        poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
        serviceManager.deployPolicy("x-aleo-6a52de9724a6e8f2", "test-policy", 1);

        SimpleV4Router v4Router = new SimpleV4Router(poolManager);
        router = ISimpleV4Router(address(v4Router));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(poolManager, router, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{ salt: salt }(poolManager, router, address(serviceManager), "x-aleo-6a52de9724a6e8f2");

        require(address(hook) == hookAddress, "Hook deployment failed");
    }
}
