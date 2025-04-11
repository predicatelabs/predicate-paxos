// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {V4SwapRouter} from "../../src/V4SwapRouter.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

contract DeployAutoWrapperAndInitPool is Script {
    INetwork private _env;
    address private _hookAddress;
    V4SwapRouter private _swapRouter;
    int24 private _tickSpacing;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool hookAddressExists = vm.envExists("HOOK_ADDRESS");
        bool swapRouterExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        require(
            networkExists && hookAddressExists && swapRouterExists,
            "All environment variables must be set if any are specified"
        );
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        _hookAddress = vm.envAddress("HOOK_ADDRESS");
        _swapRouter = V4SwapRouter(vm.envAddress("SWAP_ROUTER_ADDRESS"));
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();

        IPoolManager manager = config.poolManager;
        IERC20 wUSDL = IERC20(Currency.unwrap(tokenConfig.wUSDL));
        IERC20 USDC = IERC20(Currency.unwrap(tokenConfig.USDC));
        IERC20 USDL = IERC20(Currency.unwrap(tokenConfig.USDL));
        IHooks hook = IHooks(_hookAddress);
        _tickSpacing = 60;
        PoolKey memory predicatePoolKey = PoolKey(tokenConfig.wUSDL, tokenConfig.USDC, 0, _tickSpacing, hook);

        // initialize the auto wrapper
        uint160 autoWrapperFlags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory autoWrapperConstructorArgs =
            abi.encode(manager, ERC4626(address(wUSDL)), USDC, predicatePoolKey, _swapRouter);
        (address autoWrapperAddress, bytes32 autoWrapperSalt) = HookMiner.find(
            config.create2Deployer, autoWrapperFlags, type(AutoWrapper).creationCode, autoWrapperConstructorArgs
        );
        vm.startBroadcast();
        AutoWrapper autoWrapper = new AutoWrapper{salt: autoWrapperSalt}(
            manager, ERC4626(address(wUSDL)), Currency.wrap(address(USDC)), predicatePoolKey, _swapRouter
        );
        require(address(autoWrapper) == autoWrapperAddress, "Hook deployment failed");
        console.log("Deployed AutoWrapper at address: ", address(autoWrapper));

        // initialize the ghost pool
        PoolKey memory ghostPoolKey;
        ghostPoolKey =
            PoolKey(Currency.wrap(address(USDC)), Currency.wrap(address(USDL)), 0, _tickSpacing, IHooks(autoWrapper));
        console.log(
            "Deploying ghost pool with token0: %s and token1: %s",
            Currency.unwrap(ghostPoolKey.currency0),
            Currency.unwrap(ghostPoolKey.currency1)
        );
        uint160 ghostPoolStartingPrice = 79_228_162_514_264_337_593_543_950_336_000_000;
        manager.initialize(ghostPoolKey, ghostPoolStartingPrice);

        // set approvals
        _setApprovals(wUSDL, USDC, USDL, autoWrapper);
        vm.stopBroadcast();
    }

    function _setApprovals(IERC20 wUSDL, IERC20 USDC, IERC20 USDL, AutoWrapper autoWrapper) internal {
        // Approve autoWrapper to spend USDL from msg.sender
        USDL.approve(address(autoWrapper), type(uint256).max);
        // Approve autoWrapper to spend USDC from msg.sender
        USDC.approve(address(autoWrapper), type(uint256).max);
        // Approve autoWrapper to spend wUSDL from msg.sender
        wUSDL.approve(address(autoWrapper), type(uint256).max);
    }
}
