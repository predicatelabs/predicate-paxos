// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {PoolSetup} from "./PoolSetup.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {YBSV1_1} from "../../src/paxos/YBSV1_1.sol";
import {wYBSV1} from "../../src/paxos/wYBSV1.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";

contract AutoWrapperSetup is PoolSetup {
    AutoWrapper public wrapper;
    Currency currency0;
    Currency currency1;
    int24 tickSpacing = 60;
    PoolKey poolKey;
    YBSV1_1 ybs;

    function setUpAutoWrapper(
        address liquidityProvider
    ) internal {
        deployPoolManager();
        deployRouters();
        deployPosm();
        (currency0, currency1) = deployAndMintTokens(liquidityProvider, 100_000 ether);
        vm.startPrank(liquidityProvider);
        setApprovals(currency0, currency1);
        vm.stopPrank();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(manager, address(ybs), poolKey);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(AutoWrapper).creationCode, constructorArgs);

        wrapper = new AutoWrapper{salt: salt}(manager, address(ybs), poolKey);
        require(address(wrapper) == hookAddress, "Hook deployment failed");

        poolKey = PoolKey(currency0, currency1, 3000, tickSpacing, IHooks(wrapper));
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
