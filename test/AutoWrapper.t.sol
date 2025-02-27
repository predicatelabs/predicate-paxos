// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutoWrapper} from "../src/AutoWrapper.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TestWrapperSetup} from "./helpers/TestWrapperSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {wYBSV1} from "../src/paxos/wYBSV1.sol";
import "forge-std/Test.sol";

contract AutoWrapperTest is TestWrapperSetup, Test {
    function setUp() public override {
        super.setUp();
    }

    function testWrapAndSwap() public {
        uint256 ybsAmount = 100e18;
        ybs.approve(address(wrapper), ybsAmount);

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

        assertEq(ybs.balanceOf(address(this)), 900e18);
        assertEq(wYBS.balanceOf(address(wrapper)), 100e18);
    }

    function testUnwrapAndSwap() public {
        uint256 wrappedAmount = 100e18;
        wYBS.approve(address(wrapper), wrappedAmount);

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

        assertEq(wYBS.balanceOf(address(this)), 0);
        assertEq(ybs.balanceOf(address(wrapper)), 100e18);
    }

    function testWrapWithExactOutput() public {
        uint256 ybsAmount = 100e18;
        ybs.approve(address(wrapper), ybsAmount);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: int256(ybsAmount), sqrtPriceLimitX96: 0});

        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            wrapper.underlyingPoolKey();
        wrapper.beforeSwap(
            address(this),
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
            params,
            ""
        );

        assertEq(ybs.balanceOf(address(this)), 900e18);
        assertEq(wYBS.balanceOf(address(wrapper)), 100e18);
    }

    function testUnwrapWithExactOutput() public {
        uint256 wrappedAmount = 100e18;
        wYBS.approve(address(wrapper), wrappedAmount);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: int256(wrappedAmount), sqrtPriceLimitX96: 0});

        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            wrapper.underlyingPoolKey();
        wrapper.beforeSwap(
            address(this),
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
            params,
            ""
        );

        assertEq(wYBS.balanceOf(address(this)), 0);
        assertEq(ybs.balanceOf(address(wrapper)), 100e18);
    }

    function testRevertOnInsufficientBalance() public {
        uint256 ybsAmount = 200e18; // More than available balance
        ybs.approve(address(wrapper), ybsAmount);

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -int256(ybsAmount), sqrtPriceLimitX96: 0});

        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) =
            wrapper.underlyingPoolKey();

        vm.expectRevert();
        wrapper.beforeSwap(
            address(this),
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: tickSpacing, hooks: hooks}),
            params,
            ""
        );
    }
}
