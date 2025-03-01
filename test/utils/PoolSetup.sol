// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "./forks/DeployPermit2.sol";
import {IERC721Permit_v4} from "v4-periphery/src/interfaces/IERC721Permit_v4.sol";
import {IEIP712_v4} from "v4-periphery/src/interfaces/IEIP712_v4.sol";
import {ERC721PermitHash} from "v4-periphery/src/libraries/ERC721PermitHash.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {EasyPosm} from "./EasyPosm.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";

contract PoolSetup is DeployPermit2 {
    using EasyPosm for IPositionManager;

    uint256 constant STARTING_USER_BALANCE = 10_000_000 ether;

    // Global variables
    Currency internal currency0;
    Currency internal currency1;
    IPoolManager manager;
    IPositionManager posm;
    PoolModifyLiquidityTest lpRouter;
    ISimpleV4Router swapRouter;
    address feeController;

    function initPool(
        Currency _currency0,
        Currency _currency1,
        IHooks hooks,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) internal returns (PoolKey memory _key) {
        _key = PoolKey(_currency0, _currency1, fee, tickSpacing, hooks);
        manager.initialize(_key, sqrtPriceX96);
    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------

    function deployPoolManager() internal virtual {
        manager = IPoolManager(new PoolManager(address(this)));
    }

    function deployRouters() internal virtual {
        require(address(manager) != address(0), "Manager not deployed");
        lpRouter = new PoolModifyLiquidityTest(manager);
        SimpleV4Router v4Router = new SimpleV4Router(manager);
        swapRouter = ISimpleV4Router(address(v4Router));
    }

    function deployPosm() internal virtual {
        require(address(permit2) != address(0), "Permit2 not deployed");
        require(address(manager) != address(0), "Manager not deployed");
        etchPermit2();
        posm = IPositionManager(
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

    function deployAndMintTokens() internal {
        (MockERC20 token0, MockERC20 token1) = deployTokens();

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        console.log("Deployed Token0: %s", address(token0));
        console.log("Deployed Token1: %s", address(token1));

        token0.mint(msg.sender, STARTING_USER_BALANCE);
        token1.mint(msg.sender, STARTING_USER_BALANCE);
    }

    function initPoolAndSetApprovals(
        IHooks hook
    ) internal {
        bytes memory ZERO_BYTES = new bytes(0);

        // initialize the pool
        int24 tickSpacing = 60;
        PoolKey memory poolKey = PoolKey(currency0, currency1, 3000, tickSpacing, IHooks(hook));
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
