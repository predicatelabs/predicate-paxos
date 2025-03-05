// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {EasyPosm} from "../../test/utils/EasyPosm.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../../test/utils/forks/DeployPermit2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

/// @notice Forge script for deploying v4 & hooks
contract DeployTokensAndPool is Script, DeployPermit2 {
    using EasyPosm for IPositionManager;

    INetwork private _env;
    address private hookAddress;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool hookAddressExists = vm.envExists("HOOK_ADDRESS");
        require(networkExists && hookAddressExists, "All environment variables must be set if any are specified");
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        hookAddress = vm.envAddress("HOOK_ADDRESS");
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();

        vm.startBroadcast();
        IPoolManager manager = config.poolManager;
        ISimpleV4Router swapRouter = config.router;
        IPositionManager posm = deployPosm(manager);
        PoolModifyLiquidityTest lpRouter = deployRouters(manager);
        console.log("Deployed POSM: %s", address(posm));
        console.log("Deployed LP Router: %s", address(lpRouter));
        vm.stopBroadcast();

        // test the lifecycle (create pool, add liquidity, swap)
        vm.startBroadcast();
        setApprovalsAndMintLiquidity(manager, hookAddress, posm, lpRouter, swapRouter);
        vm.stopBroadcast();
    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------

    function deployRouters(
        IPoolManager manager
    ) internal returns (PoolModifyLiquidityTest lpRouter) {
        lpRouter = new PoolModifyLiquidityTest(manager);
    }

    function deployPosm(
        IPoolManager poolManager
    ) public returns (IPositionManager) {
        anvilPermit2();
        return IPositionManager(
            new PositionManager(poolManager, permit2, 300_000, IPositionDescriptor(address(0)), IWETH9(address(0)))
        );
    }

    function approvePosmCurrency(IPositionManager posm, Currency currency) internal {
        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        // 2. Then, the caller must approve POSM as a spender of permit2
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }

    function deployTokens() internal returns (MockERC20 token0, MockERC20 token1) {
        MockERC20 tokenA = new MockERC20("MockA", "A", 18);
        MockERC20 tokenB = new MockERC20("MockB", "B", 18);
        if (uint160(address(tokenA)) < uint160(address(tokenB))) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }
    }

    function setApprovalsAndMintLiquidity(
        IPoolManager manager,
        address hook,
        IPositionManager posm,
        PoolModifyLiquidityTest lpRouter,
        ISimpleV4Router swapRouter
    ) internal {
        (MockERC20 token0, MockERC20 token1) = deployTokens();
        console.log("Deployed Token0: %s", address(token0));
        console.log("Deployed Token1: %s", address(token1));
        token0.mint(msg.sender, 100_000 ether);
        token1.mint(msg.sender, 100_000 ether);

        bytes memory ZERO_BYTES = new bytes(0);

        // initialize the pool
        int24 tickSpacing = 60;
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // approve the tokens to the routers
        token0.approve(address(lpRouter), type(uint256).max);
        token1.approve(address(lpRouter), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        approvePosmCurrency(posm, Currency.wrap(address(token0)));
        approvePosmCurrency(posm, Currency.wrap(address(token1)));

        // add full range liquidity to the pool
        lpRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacing), TickMath.maxUsableTick(tickSpacing), 100 ether, 0
            ),
            ZERO_BYTES
        );

        posm.mint(
            poolKey,
            TickMath.minUsableTick(tickSpacing),
            TickMath.maxUsableTick(tickSpacing),
            100e18,
            10_000e18,
            10_000e18,
            msg.sender,
            block.timestamp + 300,
            ZERO_BYTES
        );
    }
}
