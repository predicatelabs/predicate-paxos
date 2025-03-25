// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

contract ApproveTokens is Script {
    INetwork private _env;
    address private _autoWrapperAddress; // this is autoWrapperHookAddress
    address private _swapRouterAddress;
    address private _predicateHookAddress;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool autoWrapperAddressExists = vm.envExists("AUTO_WRAPPER_ADDRESS");
        bool swapRouterAddressExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        bool predicateHookAddressExists = vm.envExists("PREDICATE_HOOK_ADDRESS");
        require(
            networkExists && autoWrapperAddressExists && swapRouterAddressExists && predicateHookAddressExists,
            "All environment variables must be set if any are specified"
        );
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        _autoWrapperAddress = vm.envAddress("AUTO_WRAPPER_ADDRESS");
        _swapRouterAddress = vm.envAddress("SWAP_ROUTER_ADDRESS");
        _predicateHookAddress = vm.envAddress("PREDICATE_HOOK_ADDRESS");
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();

        IERC20 wUSDL = IERC20(Currency.unwrap(tokenConfig.wUSDL));
        IERC20 USDC = IERC20(Currency.unwrap(tokenConfig.USDC));
        IERC20 USDL = IERC20(Currency.unwrap(tokenConfig.USDL));

        vm.startBroadcast();
        // Approve autoWrapper to spend USDC from msg.sender
        USDL.approve(_autoWrapperAddress, type(uint256).max);
        // Approve autoWrapper to spend USDC from msg.sender
        USDC.approve(_autoWrapperAddress, type(uint256).max);
        // Approve autoWrapper to spend wUSDL from msg.sender
        wUSDL.approve(_autoWrapperAddress, type(uint256).max);
        // Approve wUSDL to spend USDL from msg.sender
        USDL.approve(address(wUSDL), type(uint256).max);
        vm.stopBroadcast();
    }
}
