// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {MetaCoinTestSetup} from "@predicate-test/helpers/utility/MetaCoinTestSetup.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {PoolSetup} from "./PoolSetup.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";

contract PredicateHookSetup is MetaCoinTestSetup, PoolSetup {
    PredicateHook public hook;
    Currency public currency0;
    Currency public currency1;
    int24 public tickSpacing = 60;
    PoolKey public poolKey;

    function _setUpPredicateHook(
        address _liquidityProvider
    ) internal {
        address _owner = makeAddr("owner");
        _deployPoolManager();
        _deployRouters();
        _deployPosm();
        (currency0, currency1) = _deployAndMintTokens(_liquidityProvider, 100_000e6);
        vm.startPrank(_liquidityProvider);
        _setTokenApprovalForRouters(currency0);
        _setTokenApprovalForRouters(currency1);
        vm.stopPrank();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);
        bytes memory constructorArgs = abi.encode(
            manager,
            PositionManager(payable(address(posm))),
            swapRouter,
            address(serviceManager),
            "testPolicy",
            _owner,
            currency0,
            Currency.unwrap(currency1)
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{salt: salt}(
            manager,
            PositionManager(payable(address(posm))),
            swapRouter,
            address(serviceManager),
            "testPolicy",
            _owner,
            currency0,
            Currency.unwrap(currency1)
        );
        require(address(hook) == hookAddress, "Hook deployment failed");

        poolKey = PoolKey(currency0, currency1, 0, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        address[] memory authorizedLps = new address[](3);
        authorizedLps[0] = _liquidityProvider;
        vm.prank(_owner);
        hook.addAuthorizedLPs(authorizedLps);

        require(hook.isAuthorizedLP(_liquidityProvider), "Liquidity Provider not authorized");

        vm.startPrank(_liquidityProvider);
        _provisionLiquidity(Constants.SQRT_PRICE_1_1, tickSpacing, poolKey, _liquidityProvider, 100e6, 100e6);
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
