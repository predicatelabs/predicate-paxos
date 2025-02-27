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
import {HookMiner} from "./utils/HookMiner.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "forge-std/Test.sol";

contract AutoWrapperTest is Test {
    AutoWrapper public wrapper;
    MockERC20 public ybs;
    wYBSV1 public wYBS;
    MockERC20 public usdc;
    IPoolManager public poolManager;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function setUp() public {
        poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

        ybs = new MockERC20("YBS Token", "YBS", 18);
        wYBS = new wYBSV1();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(wYBS)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(ybs), poolKey);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(AutoWrapper).creationCode, constructorArgs);

        wrapper = new AutoWrapper{salt: salt}(poolManager, address(ybs), poolKey);
        require(address(wrapper) == hookAddress, "AutoWrapper deployed at wrong address");

        ybs.mint(address(this), 1000e18);
        usdc.mint(address(this), 1000e6);
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
        uint256 ybsAmount = 200e18;
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
