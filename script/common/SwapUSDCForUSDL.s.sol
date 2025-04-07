// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {CommonBase} from "forge-std/Base.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INetwork} from "./INetwork.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {Script} from "forge-std/Script.sol";
import {StdChains} from "forge-std/StdChains.sol";
import {StdCheatsSafe} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {V4SwapRouter} from "../../src/V4SwapRouter.sol";

contract SwapScript is Script {
    uint24 lpFee = 0; // 0.30%
    int24 tickSpacing = 60;
    Currency private _currency0;
    Currency private _currency1;
    INetwork private _env;
    address private _autowrapperHookAddress;
    V4SwapRouter private _swapRouter;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool autoWrapperHookAddress = vm.envExists("AUTO_WRAPPER_HOOK_ADDRESS");
        bool swapRouterAddressExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        require(
            networkExists && autoWrapperHookAddress && swapRouterAddressExists,
            "All environment variables must be set if any are specified"
        );
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        _autowrapperHookAddress = vm.envAddress("AUTO_WRAPPER_HOOK_ADDRESS");
        _swapRouter = V4SwapRouter(vm.envAddress("SWAP_ROUTER_ADDRESS"));
    }

    function run() public {
        _init();
        vm.label(address(0x8F2c925603c4ba055779475F14241E3c9ee7c1be), "SWAP_ROUTER_CONTRACT");
        vm.label(address(0x084B1d8B3f5cb834Fe15C39B18F91Faf2fbE2880), "PREDICATE_HOOK_CONTRACT");
        vm.label(address(0x599d955C3504898952775c83Fd826A9f7339a8C8), "AUTOWRAPPER_HOOK_CONTRACT");
        vm.label(address(0x7751E2F4b8ae93EF6B79d86419d42FE3295A4559), "WRAPPED_USDL_TOKEN");
        vm.label(address(0xbdC7c08592Ee4aa51D06C27Ee23D5087D65aDbcD), "USDL_TOKEN");
        vm.label(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), "USDC_TOKEN");
        vm.label(address(0x000000000004444c5dc75cB358380D2e3dE08A90), "POOLMANAGER");
        vm.label(address(0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2), "SERVICEMANAGER_CONTRACT");
        INetwork.Config memory config = _env.config();
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        address tokenIn = Currency.unwrap(tokenConfig.USDC);
        address tokenOut = Currency.unwrap(tokenConfig.USDL);
        address recipient = msg.sender;
        uint128 amountIn = 1e6; // 1 wUSDL
        uint128 amountOutMin = 1; // accept any amount out
        uint160 sqrtPriceLimitX96 = 0;
        PoolKey memory key = PoolKey({
            currency0: tokenConfig.USDC,
            currency1: tokenConfig.USDL,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(_autowrapperHookAddress)
        });
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: true,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            hookData: abi.encode("0x")
        });
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams); // swap params
        params[1] = abi.encode(key.currency0, 1e6); // settle currency0
        params[2] = abi.encode(key.currency1, 1e18); // take currency1
        vm.startBroadcast();
        _swapRouter.execute(abi.encode(actions, params));
        vm.stopBroadcast();
    }
}
