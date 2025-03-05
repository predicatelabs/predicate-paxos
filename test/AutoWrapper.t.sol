// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutoWrapper} from "../src/AutoWrapper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {wYBSV1} from "../src/paxos/wYBSV1.sol";
import {YBSV1_1} from "../src/paxos/YBSV1_1.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {AutoWrapperSetup} from "./utils/AutoWrapperSetup.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Test} from "forge-std/Test.sol";

contract AutoWrapperTest is AutoWrapperSetup, Test {
    address liquidityProvider;

    function setUp() public {
        liquidityProvider = makeAddr("liquidityProvider");
        setUpAutoWrapper(liquidityProvider);
    }

    // function testSwapZeroForOne() public {
    //     vm.deal(address(wrapper), 1e18);
    //     vm.prank(liquidityProvider);

    //     PoolKey memory key = getPoolKey();
    //     IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
    //         zeroForOne: true,
    //         amountSpecified: 1e18,
    //         sqrtPriceLimitX96: uint160(4_295_128_740)
    //     });

    //     IERC20 token0 = IERC20(Currency.unwrap(key.currency0));
    //     IERC20 token1 = IERC20(Currency.unwrap(key.currency1));

    //     uint256 balance0 = token0.balanceOf(liquidityProvider);
    //     uint256 balance1 = token1.balanceOf(liquidityProvider);

    //     vm.prank(address(liquidityProvider));
    //     swapRouter.swap(key, params, abi.encode(liquidityProvider, 0));

    //     require(token0.balanceOf(liquidityProvider) < balance0, "Token0 balance should decrease");
    //     require(token1.balanceOf(liquidityProvider) > balance1, "Token1 balance should increase");
    // }

    function testWrapAndSwap() public {
        (YBSV1_1 _ybs, wYBSV1 _wYBS) = initializeYBS();
        uint256 ybsAmount = 100e18;
        uint256 wYbsAmount = 100e18;
        _ybs.approve(address(wrapper), ybsAmount);
        _wYBS.approve(address(wrapper), wYbsAmount);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(ybsAmount), sqrtPriceLimitX96: 0});

        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            wrapper.underlyingPoolKey();
        wrapper.beforeSwap(
            address(this),
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
            params,
            ""
        );

        require(_ybs.balanceOf(address(this)) == 900e18, "YBS balance should decrease");
        require(_wYBS.balanceOf(address(wrapper)) == 100e18, "wYBS balance should increase");
    }

    function testUnwrapAndSwap() public {
        (YBSV1_1 _ybs, wYBSV1 _wYBS) = initializeYBS();
        uint256 wrappedAmount = 100e18;
        _wYBS.approve(address(wrapper), wrappedAmount);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(wrappedAmount), sqrtPriceLimitX96: 0});

        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            wrapper.underlyingPoolKey();
        wrapper.beforeSwap(
            address(this),
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
            params,
            ""
        );

        require(_wYBS.balanceOf(address(this)) == 0, "wYBS balance should decrease");
        require(_ybs.balanceOf(address(wrapper)) == 100e18, "YBS balance should increase");
    }

    // function testWrapWithExactOutput() public {
    //     (YBSV1_1 _ybs, wYBSV1 _wYBS) = initializeYBS();
    //     uint256 ybsAmount = 100e18;
    //     _ybs.approve(address(wrapper), ybsAmount);

    //     IPoolManager.SwapParams memory params =
    //         IPoolManager.SwapParams({zeroForOne: true, amountSpecified: int256(ybsAmount), sqrtPriceLimitX96: 0});

    //     (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
    //         wrapper.underlyingPoolKey();
    //     wrapper.beforeSwap(
    //         address(this),
    //         PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
    //         params,
    //         ""
    //     );

    //     require(_ybs.balanceOf(address(this)) == 900e18, "YBS balance should decrease");
    //     require(_wYBS.balanceOf(address(wrapper)) == 100e18, "wYBS balance should increase");
    // }

    // function testUnwrapWithExactOutput() public {
    //     (YBSV1_1 _ybs, wYBSV1 _wYBS) = initializeYBS();
    //     uint256 wrappedAmount = 100e18;
    //     _wYBS.approve(address(wrapper), wrappedAmount);

    //     IPoolManager.SwapParams memory params =
    //         IPoolManager.SwapParams({zeroForOne: false, amountSpecified: int256(wrappedAmount), sqrtPriceLimitX96: 0});

    //     (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
    //         wrapper.underlyingPoolKey();
    //     wrapper.beforeSwap(
    //         address(this),
    //         PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
    //         params,
    //         ""
    //     );

    //     require(_wYBS.balanceOf(address(this)) == 0, "wYBS balance should decrease");
    //     require(_ybs.balanceOf(address(wrapper)) == 100e18, "YBS balance should increase");
    // }

    // function testRevertOnInsufficientBalance() public {
    //     ybs.grantRole(ybs.SUPPLY_CONTROLLER_ROLE(), address(this));
    //     ybs.increaseSupply(100e18);
    //     uint256 ybsAmount = 200e18;
    //     ybs.approve(address(wrapper), ybsAmount);

    //     IPoolManager.SwapParams memory params =
    //         IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(ybsAmount), sqrtPriceLimitX96: 0});

    //     (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
    //         wrapper.underlyingPoolKey();

    //     vm.expectRevert();
    //     wrapper.beforeSwap(
    //         address(this),
    //         PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
    //         params,
    //         ""
    //     );
    // }

    // function testWrapAndUnwrap() public {
    //     ybs.grantRole(ybs.SUPPLY_CONTROLLER_ROLE(), address(this));
    //     ybs.increaseSupply(100e18);

    //     uint256 ybsAmount = 50e18;
    //     ybs.approve(address(wrapper), ybsAmount);

    //     IPoolManager.SwapParams memory wrapParams =
    //         IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(ybsAmount), sqrtPriceLimitX96: 0});

    //     (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
    //         wrapper.underlyingPoolKey();

    //     uint256 ybsBalanceBefore = ybs.balanceOf(address(this));
    //     uint256 wYbsBalanceBefore = wYBS.balanceOf(address(this));

    //     wrapper.beforeSwap(
    //         address(this),
    //         PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
    //         wrapParams,
    //         ""
    //     );

    //     require(ybs.balanceOf(address(this)) == ybsBalanceBefore - ybsAmount, "YBS balance should decrease");
    //     require(wYBS.balanceOf(address(this)) == wYbsBalanceBefore + ybsAmount, "wYBS balance should increase");

    //     wYBS.approve(address(wrapper), ybsAmount);

    //     IPoolManager.SwapParams memory unwrapParams =
    //         IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(ybsAmount), sqrtPriceLimitX96: 0});

    //     ybsBalanceBefore = ybs.balanceOf(address(this));
    //     wYbsBalanceBefore = wYBS.balanceOf(address(this));

    //     wrapper.beforeSwap(
    //         address(this),
    //         PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
    //         unwrapParams,
    //         ""
    //     );

    //     require(ybs.balanceOf(address(this)) == ybsBalanceBefore + ybsAmount, "YBS balance should increase");
    //     require(wYBS.balanceOf(address(this)) == wYbsBalanceBefore - ybsAmount, "wYBS balance should decrease");
    // }
}
