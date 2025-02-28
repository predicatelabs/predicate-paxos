// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {STMSetup} from "@predicate-test/helpers/utility/STMSetup.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {Fixtures} from "./Fixtures.sol";

contract PredicateHookSetup is STMSetup, Fixtures {
    PredicateHook public predicateHook;
    IPoolManager public manager;
    ISimpleV4Router public router;

    function setUpHook() internal {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        setUpPoolManager();
        setUpPermissions();
        serviceManager.deployPolicy("x-aleo-6a52de9724a6e8f2", "test-policy", 1);

        SimpleV4Router v4Router = new SimpleV4Router(poolManager);
        router = ISimpleV4Router(address(v4Router));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        bytes memory constructorArgs =
            abi.encode(poolManager, router, address(serviceManager), "x-aleo-6a52de9724a6e8f2");
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(PredicateHook).creationCode, constructorArgs);

        hook = new PredicateHook{salt: salt}(poolManager, router, address(serviceManager), "x-aleo-6a52de9724a6e8f2");

        require(address(hook) == hookAddress, "Hook deployment failed");
    }

    function setUpPoolManager() internal {
        // todo : set up pool manager
        poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    }

    function setUpPermissions() internal {} // todo: set up permissions here
}

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";
// import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
// import {Hooks} from "v4-core/src/libraries/Hooks.sol";
// import {TickMath} from "v4-core/src/libraries/TickMath.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
// import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
// import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
// import {Counter} from "../src/Counter.sol";
// import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

// import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
// import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
// import {EasyPosm} from "./utils/EasyPosm.sol";
// import {Fixtures} from "./utils/Fixtures.sol";

// contract CounterTest is Test, Fixtures {
//     using EasyPosm for IPositionManager;
//     using PoolIdLibrary for PoolKey;
//     using CurrencyLibrary for Currency;
//     using StateLibrary for IPoolManager;

//     Counter hook;
//     PoolId poolId;

//     uint256 tokenId;
//     int24 tickLower;
//     int24 tickUpper;

//     function setUp() public {
//         // creates the pool manager, utility routers, and test tokens
//         deployFreshManagerAndRouters();
//         deployMintAndApprove2Currencies();

//         deployAndApprovePosm(manager);

//         // Deploy the hook to an address with the correct flags
//         address flags = address(
//             uint160(
//                 Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
//                     | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
//             ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
//         );
//         bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
//         deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
//         hook = Counter(flags);

//         // Create the pool
//         key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
//         poolId = key.toId();
//         manager.initialize(key, SQRT_PRICE_1_1);

//         // Provide full-range liquidity to the pool
//         tickLower = TickMath.minUsableTick(key.tickSpacing);
//         tickUpper = TickMath.maxUsableTick(key.tickSpacing);

//         uint128 liquidityAmount = 100e18;

//         (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
//             SQRT_PRICE_1_1,
//             TickMath.getSqrtPriceAtTick(tickLower),
//             TickMath.getSqrtPriceAtTick(tickUpper),
//             liquidityAmount
//         );

//         (tokenId,) = posm.mint(
//             key,
//             tickLower,
//             tickUpper,
//             liquidityAmount,
//             amount0Expected + 1,
//             amount1Expected + 1,
//             address(this),
//             block.timestamp,
//             ZERO_BYTES
//         );
//     }
// }
