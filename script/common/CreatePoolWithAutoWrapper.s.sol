// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
// import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
// import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
// import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
// import {IERC20} from "forge-std/interfaces/IERC20.sol";
// import {INetwork} from "./INetwork.sol";
// import {NetworkSelector} from "./NetworkSelector.sol";
// import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
// import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
// import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
// import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

// contract CreatePoolWithAutoWrapper is Script {
//     using CurrencyLibrary for Currency;

//     Currency private USDL;
//     Currency private USDC;
//     Currency private wUSDL;
//     PositionManager private posm;
//     IAllowanceTransfer private permit2;
//     ISimpleV4Router private swapRouter;

//     INetwork private _env;
//     address private autoWrapperHookAddress;

//     function _init() internal {
//         bool networkExists = vm.envExists("NETWORK");
//         bool autoWrapperHookAddressExists = vm.envExists("AUTO_WRAPPER_HOOK_ADDRESS");
//         bool swapRouterExists = vm.envExists("SWAP_ROUTER_ADDRESS");
//         require(
//             networkExists && autoWrapperHookAddressExists && swapRouterExists,
//             "All environment variables must be set if any are specified"
//         );
//         string memory _network = vm.envString("NETWORK");
//         _env = new NetworkSelector().select(_network);
//         autoWrapperHookAddress = vm.envAddress("AUTO_WRAPPER_HOOK_ADDRESS");
//         swapRouter = ISimpleV4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));
//     }

//     /////////////////////////////////////

//     function run() external {
//         _init();
//         INetwork.Config memory config = _env.config();
//         INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
//         // --------------------------------- //
//         posm = config.positionManager;
//         permit2 = config.permit2;
//         USDL = tokenConfig.USDL;
//         USDC = tokenConfig.USDC;

//         // tokens should be sorted
//         PoolKey memory pool =
//             PoolKey({currency0: USDL, currency1: USDC, fee: 0, tickSpacing: 60, hooks: IHooks(autoWrapperHookAddress)});
//         bytes memory hookData = new bytes(0);

//         // --------------------------------- //
//         // multicall parameters
//         bytes[] memory params = new bytes[](1);

//         // initialize pool
//         params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, Constants.SQRT_PRICE_1_1, hookData);

//         vm.startBroadcast();
//         tokenApprovals();
//         posm.multicall(params);
//         vm.stopBroadcast();
//     }

//     function tokenApprovals() public {
//         require(!USDL.isAddressZero(), "Currency must not be zero");

//         IERC20 token0 = IERC20(Currency.unwrap(USDL));

//         // approve USDL
//         token0.approve(address(permit2), type(uint256).max);
//         permit2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
//         token0.approve(address(swapRouter), type(uint256).max);

//         // approve wUSDL
//         IERC20(Currency.unwrap(USDL)).approve(Currency.unwrap(wUSDL), type(uint256).max);
//     }
// }
