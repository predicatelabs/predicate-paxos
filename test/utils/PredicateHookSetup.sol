// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";
import {MetaCoinTestSetup} from "@predicate-test/helpers/utility/MetaCoinTestSetup.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {PoolSetup} from "./PoolSetup.sol";

contract PredicateHookSetup is MetaCoinTestSetup, PoolSetup {
    PredicateHook public hook;
    Currency currency0;
    Currency currency1;
    int24 tickSpacing = 60;
    PoolKey poolKey;

    function setUpPredicateHook(
        address liquidityProvider
    ) internal {
        deployPoolManager();
        deployRouters();
        deployPosm();
        (currency0, currency1) = deployAndMintTokens(liquidityProvider, 100_000 ether);
        vm.startPrank(liquidityProvider);
        setApprovals(currency0, currency1);
        vm.stopPrank();

        // deploy policy for test
        serviceManager.deployPolicy("x-aleo-6a52de9724a6e8f2", "test-policy", 1);

        // create hook here
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(manager, swapRouter, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{salt: salt}(manager, swapRouter, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        require(address(hook) == hookAddress, "Hook deployment failed");

        // initialize the pool
        poolKey = PoolKey(currency0, currency1, 3000, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        vm.startPrank(liquidityProvider);
        provisionLiquidity(tickSpacing, poolKey, 100 ether, liquidityProvider, 100_000 ether, 100_000 ether);
        vm.stopPrank();
    }

    function getPoolKey() public view returns (PoolKey memory) {
        return poolKey;
    }

    function getCurrency0() public view returns (Currency) {
        return currency0;
    }

    function getCurrency1() public view returns (Currency) {
        return currency1;
    }

    function getTickSpacing() public view returns (int24) {
        return tickSpacing;
    }
}
