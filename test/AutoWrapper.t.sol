// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {BaseTokenWrapperHook} from "@uniswap/v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import {AutoWrapper} from "../src/AutoWrapper.sol";
import {wYBSV1} from "../src/paxos/wYBSV1.sol";

contract AutoWrapperTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    AutoWrapper public wrapper;
    wYBSV1 public wYBS;
    MockERC20 public ybs;
    PoolKey poolKey;
    uint160 initSqrtPriceX96;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        deployFreshManagerAndRouters();

        ybs = new MockERC20("YBS Token", "YBS", 18);
        wYBS = new wYBSV1();

        wrapper = AutoWrapper(
            payable(
                address(
                    uint160(
                        type(uint160).max & clearAllHookPermissionsMask | Hooks.BEFORE_SWAP_FLAG
                            | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                            | Hooks.BEFORE_INITIALIZE_FLAG
                    )
                )
            )
        );
        deployCodeTo("AutoWrapper", abi.encode(manager, wYBS), address(wrapper));

        poolKey = PoolKey({
            currency0: Currency.wrap(address(ybs)),
            currency1: Currency.wrap(address(wYBS)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(wrapper))
        });

        initSqrtPriceX96 = uint160(TickMath.getSqrtPriceAtTick(0));
        manager.initialize(poolKey, initSqrtPriceX96);

        ybs.mint(alice, 100 ether);
        ybs.mint(bob, 100 ether);
        ybs.mint(address(this), 200 ether);
        ybs.mint(address(wYBS), 200 ether);

        wYBS.mint(100 ether, alice);
        wYBS.mint(100 ether, bob);
        wYBS.mint(200 ether, address(this));

        _addUnrelatedLiquidity();
    }

    function test_initialization() public view {
        assertEq(address(wrapper.wYBS()), address(wYBS));
        assertEq(Currency.unwrap(wrapper.wrapperCurrency()), address(wYBS));
        assertEq(Currency.unwrap(wrapper.underlyingCurrency()), address(ybs));
    }

    function test_wrap_exact_input() public {
        uint256 wrapAmount = 1 ether;
        uint256 expectedOutput = wYBS.previewDeposit(wrapAmount);

        vm.startPrank(alice);
        ybs.approve(address(swapRouter), type(uint256).max);

        uint256 aliceYBSBefore = ybs.balanceOf(address(alice));
        uint256 aliceWYBSBefore = wYBS.balanceOf(address(alice));
        uint256 managerYBSBefore = ybs.balanceOf(address(manager));
        uint256 managerWYBSBefore = wYBS.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, // YBS (0) to wYBS (1)
                amountSpecified: -int256(wrapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            testSettings,
            ""
        );

        assertEq(aliceYBSBefore - ybs.balanceOf(alice), wrapAmount);
        assertEq(wYBS.balanceOf(alice) - aliceWYBSBefore, expectedOutput);
        assertEq(managerYBSBefore, ybs.balanceOf(address(manager)));
        assertEq(managerWYBSBefore, wYBS.balanceOf(address(manager)));
    }

    function test_unwrap_exactInput() public {
        uint256 unwrapAmount = 1 ether;
        uint256 expectedOutput = wYBS.previewRedeem(unwrapAmount);

        vm.startPrank(alice);
        wYBS.approve(address(swapRouter), type(uint256).max);

        uint256 aliceYBSBefore = ybs.balanceOf(alice);
        uint256 aliceWYBSBefore = wYBS.balanceOf(alice);
        uint256 managerYBSBefore = ybs.balanceOf(address(manager));
        uint256 managerWYBSBefore = wYBS.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false, // wYBS (1) to YBS (0)
                amountSpecified: -int256(unwrapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(ybs.balanceOf(alice) - aliceYBSBefore, expectedOutput);
        assertEq(aliceWYBSBefore - wYBS.balanceOf(alice), unwrapAmount);
        assertEq(managerYBSBefore, ybs.balanceOf(address(manager)));
        assertEq(managerWYBSBefore, wYBS.balanceOf(address(manager)));
    }

    function test_wrap_exactOutput() public {
        uint256 wrapAmount = 1 ether;
        uint256 expectedInput = wYBS.previewDeposit(wrapAmount);

        vm.startPrank(alice);
        ybs.approve(address(swapRouter), type(uint256).max);

        uint256 aliceYBSBefore = ybs.balanceOf(alice);
        uint256 aliceWYBSBefore = wYBS.balanceOf(alice);
        uint256 managerYBSBefore = ybs.balanceOf(address(manager));
        uint256 managerWYBSBefore = wYBS.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, // YBS (0) to wYBS (1)
                amountSpecified: int256(wrapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(aliceYBSBefore - ybs.balanceOf(alice), expectedInput);
        assertEq(wYBS.balanceOf(alice) - aliceWYBSBefore, wrapAmount);
        assertEq(managerYBSBefore, ybs.balanceOf(address(manager)));
        assertEq(managerWYBSBefore, wYBS.balanceOf(address(manager)));
    }

    function test_unwrap_exactOutput() public {
        uint256 unwrapAmount = 1 ether;
        uint256 expectedInput = wYBS.previewRedeem(unwrapAmount);

        vm.startPrank(alice);
        wYBS.approve(address(swapRouter), type(uint256).max);

        uint256 aliceYBSBefore = ybs.balanceOf(alice);
        uint256 aliceWYBSBefore = wYBS.balanceOf(alice);
        uint256 managerYBSBefore = ybs.balanceOf(address(manager));
        uint256 managerWYBSBefore = wYBS.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false, // wYBS (1) to YBS (0)
                amountSpecified: int256(unwrapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(ybs.balanceOf(alice) - aliceYBSBefore, unwrapAmount);
        assertEq(aliceWYBSBefore - wYBS.balanceOf(alice), expectedInput);
        assertEq(managerYBSBefore, ybs.balanceOf(address(manager)));
        assertEq(managerWYBSBefore, wYBS.balanceOf(address(manager)));
    }

    function test_revertAddLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(wrapper),
                IHooks.beforeAddLiquidity.selector,
                abi.encodeWithSelector(BaseTokenWrapperHook.LiquidityNotAllowed.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000e18,
                salt: bytes32(0)
            }),
            ""
        );
    }

    function test_revertInvalidPoolInitialization() public {
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(ybs)),
            currency1: Currency.wrap(address(wYBS)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(wrapper))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(wrapper),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(BaseTokenWrapperHook.InvalidPoolFee.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(invalidKey, initSqrtPriceX96);

        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        (Currency currency0, Currency currency1) = address(randomToken) < address(wYBS)
            ? (Currency.wrap(address(randomToken)), Currency.wrap(address(wYBS)))
            : (Currency.wrap(address(wYBS)), Currency.wrap(address(randomToken)));
        invalidKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(address(wrapper))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(wrapper),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(BaseTokenWrapperHook.InvalidPoolToken.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(invalidKey, initSqrtPriceX96);
    }

    function _addUnrelatedLiquidity() internal {
        PoolKey memory unrelatedPoolKey = PoolKey({
            currency0: Currency.wrap(address(ybs)),
            currency1: Currency.wrap(address(wYBS)),
            fee: 100,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        manager.initialize(unrelatedPoolKey, uint160(TickMath.getSqrtPriceAtTick(0)));

        ybs.approve(address(modifyLiquidityRouter), type(uint256).max);
        wYBS.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity(
            unrelatedPoolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1000e18,
                salt: bytes32(0)
            }),
            ""
        );
    }
}
