// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
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
        setTokenApprovalForRouters(currency0);
        setTokenApprovalForRouters(currency1);
        vm.stopPrank();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG);
        bytes memory constructorArgs = abi.encode(manager, swapRouter, address(serviceManager), "testPolicy");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{salt: salt}(manager, swapRouter, address(serviceManager), "testPolicy");
        require(address(hook) == hookAddress, "Hook deployment failed");

        poolKey = PoolKey(currency0, currency1, 3000, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        address[] memory authorizedLps = new address[](4);
        authorizedLps[0] = liquidityProvider;
        authorizedLps[1] = address(lpRouter);
        authorizedLps[2] = address(posm);
        authorizedLps[3] = address(this);
        vm.prank(hook.owner());
        hook.addAuthorizedLP(authorizedLps);

        require(hook.isAuthorizedLP(liquidityProvider), "LP not authorized");
        require(hook.isAuthorizedLP(address(lpRouter)), "LP Router not authorized");
        require(hook.isAuthorizedLP(address(posm)), "POSM not authorized");
        require(hook.isAuthorizedLP(address(this)), "This contract not authorized");

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
