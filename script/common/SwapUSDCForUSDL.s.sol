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
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        vm.label(address(_swapRouter), "SWAP_ROUTER_CONTRACT");
        vm.label(_autowrapperHookAddress, "AUTOWRAPPER_HOOK_CONTRACT");
        vm.label(Currency.unwrap(tokenConfig.wUSDL), "WRAPPED_USDL_TOKEN");
        vm.label(Currency.unwrap(tokenConfig.USDL), "USDL_TOKEN");
        vm.label(Currency.unwrap(tokenConfig.USDC), "USDC_TOKEN");
        vm.label(address(0x000000000004444c5dc75cB358380D2e3dE08A90), "POOLMANAGER");
        vm.label(address(0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2), "SERVICEMANAGER_CONTRACT");

        _tokenApprovals();
        // swapUSDForUSDLExactIn();
        swapUSDLForUSDCExactIn();
        // swapUSDLForUSDCExactOut();
    }

    function _tokenApprovals() internal {
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        IERC20 token0 = IERC20(Currency.unwrap(tokenConfig.USDC));
        IERC20 token1 = IERC20(Currency.unwrap(tokenConfig.USDL));
        vm.startBroadcast();
        token0.approve(address(_swapRouter), type(uint256).max);
        token1.approve(address(_swapRouter), type(uint256).max);
        vm.stopBroadcast();
    }

    function swapUSDForUSDLExactIn() public {
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        uint128 amountIn = 1e6; // 1 USDC
        uint128 amountOutMin = 1e17; // accepts min 0.1 USDL out
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
        params[1] = abi.encode(key.currency0, amountIn); // settle currency0
        params[2] = abi.encode(key.currency1, amountOutMin); // take currency1
        vm.startBroadcast();
        _swapRouter.execute(abi.encode(actions, params));
        vm.stopBroadcast();
    }

    function swapUSDLForUSDCExactIn() public {
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        uint128 amountIn = 1e18; // 1 USDL
        uint128 amountOutMin = 9e5; // accepts min 0.9 USDC out
        PoolKey memory key = PoolKey({
            currency0: tokenConfig.USDC,
            currency1: tokenConfig.USDL,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(_autowrapperHookAddress)
        });
        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            hookData: abi.encode("0x")
        });
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE), uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.TAKE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key.currency1, amountIn + 1, true); // settle currency1
        params[1] = abi.encode(swapParams); // swap params
        params[2] = abi.encode(key.currency0, amountOutMin); // take currency0
        params[3] = abi.encode(key.currency1, 0); // take currency1
        vm.startBroadcast();
        _swapRouter.execute(abi.encode(actions, params));
        vm.stopBroadcast();
    }

    function swapUSDLForUSDCExactOut() public {
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();
        uint128 amountOut = 1e6; // 1 USDC
        uint128 amountInMax = 2e18; // accepts max 2 USDL in
        PoolKey memory key = PoolKey({
            currency0: tokenConfig.USDC,
            currency1: tokenConfig.USDL,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(_autowrapperHookAddress)
        });
        IV4Router.ExactOutputSingleParams memory swapParams = IV4Router.ExactOutputSingleParams({
            poolKey: key,
            zeroForOne: false,
            amountOut: amountOut,
            amountInMaximum: amountInMax,
            hookData: abi.encode("0x")
        });
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE),
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.TAKE_ALL),
            uint8(Actions.TAKE_ALL)
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(key.currency1, amountInMax, true); // settle currency1
        params[1] = abi.encode(swapParams); // swap params
        params[2] = abi.encode(key.currency0, amountOut); // take currency0
        params[3] = abi.encode(key.currency1, 0); // take currency1

        vm.startBroadcast();
        _swapRouter.execute(abi.encode(actions, params));
        vm.stopBroadcast();
    }
}
