// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {YBSV1_1} from "../../src/paxos/YBSV1_1.sol";
import {wYBSV1} from "../../src/paxos/wYBSV1.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {MetaCoinTestSetup} from "@predicate-test/helpers/utility/MetaCoinTestSetup.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {PoolSetup} from "./PoolSetup.sol";

contract AutoWrapperSetup is MetaCoinTestSetup, PoolSetup {
    PredicateHook public predicateHook;
    AutoWrapper public autoWrapper;
    Currency currency0;
    Currency currency1;
    Currency ybs;
    int24 tickSpacing = 60;
    PoolKey predicatePoolKey;
    PoolKey ghostPoolKey;
    // YBSV1_1 ybs;
    wYBSV1 wYBS;

    function setUpHooksAndPools(
        address liquidityProvider
    ) internal {
        // deploy pool manager, routers and posm
        deployPoolManager();
        deployRouters();
        deployPosm();

        // deploy tokens
        (currency0, ybs) = deployAndMintTokens(liquidityProvider, 100_000_000 ether);
        deployWYBS(liquidityProvider);
        currency1 = Currency.wrap(address(wYBS));

        // set approvals
        vm.startPrank(liquidityProvider);
        setApprovals(currency0, currency1); // currency1 is wYBS
        setApprovals(ybs);
        vm.stopPrank();

        // create hook here
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs = abi.encode(manager, swapRouter, address(serviceManager), "testPolicy");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        predicateHook = new PredicateHook{salt: salt}(manager, swapRouter, address(serviceManager), "testPolicy");
        require(address(predicateHook) == hookAddress, "Hook deployment failed");

        // initialize the pool
        predicatePoolKey = PoolKey(currency0, currency1, 3000, tickSpacing, IHooks(predicateHook));
        manager.initialize(predicatePoolKey, Constants.SQRT_PRICE_1_1);

        // initialize the auto wrapper
        constructorArgs = abi.encode(manager, Currency.unwrap(ybs), predicatePoolKey);
        (hookAddress, salt) = HookMiner.find(address(this), flags, type(AutoWrapper).creationCode, constructorArgs);
        autoWrapper = new AutoWrapper{salt: salt}(manager, Currency.unwrap(ybs), predicatePoolKey);
        require(address(autoWrapper) == hookAddress, "Hook deployment failed");

        // initialize the ghost pool
        ghostPoolKey = PoolKey(currency0, ybs, 3000, tickSpacing, IHooks(autoWrapper));
        manager.initialize(ghostPoolKey, Constants.SQRT_PRICE_1_1);

        // mint wYBS shares to liquidity provider
        vm.startPrank(liquidityProvider);
        wYBS.deposit(1_000_000 ether, liquidityProvider);
        vm.stopPrank();

        // provision liquidity
        vm.startPrank(liquidityProvider);
        provisionLiquidity(tickSpacing, predicatePoolKey, 100 ether, liquidityProvider, 100_000 ether, 100_000 ether);
        vm.stopPrank();
    }

    function deployWYBS(
        address liquidityProvider
    ) internal {
        wYBSV1 impl = new wYBSV1();

        /// @notice Encode initializer data
        bytes memory initData = abi.encodeCall(
            wYBSV1.initialize,
            (
                "Wrapped Yield Bearing Stablecoin",
                "wYBS",
                IERC20Upgradeable(Currency.unwrap(ybs)),
                liquidityProvider,
                liquidityProvider,
                liquidityProvider
            )
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl), // wYBS
            liquidityProvider,
            initData // initialization call data
        );
        wYBS = wYBSV1(address(proxy));
    }

    function getPredicatePoolKey() public view returns (PoolKey memory) {
        return predicatePoolKey;
    }

    function getPoolKey() public view returns (PoolKey memory) {
        return ghostPoolKey;
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
