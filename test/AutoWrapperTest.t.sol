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

import {MockUSDL} from "./mocks/MockUSDL.sol";
import {MockWUSDL} from "./mocks/MockWUDSL.sol";

import {AutoWrapper} from "src/AutoWrapper.sol";
import {IwYBSV1} from "src/interfaces/IwYBSV1.sol";
import {IYBSV1_1} from "src/interfaces/IYBSV1_1.sol";

contract AutoWrapperTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    AutoWrapper public hook;
    MockWUSDL public wUSDL;
    MockUSDL public USDL;
    PoolKey poolKey;
    uint160 initSqrtPriceX96;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        deployFreshManagerAndRouters();

        USDL = new MockUSDL("Lift Dollar", "USDL", 18);
        wUSDL = new MockWUSDL(address(USDL));

        hook = AutoWrapper(
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
        deployCodeTo("AutoWrapper", abi.encode(manager, wUSDL), address(hook));

        poolKey = PoolKey({
            currency0: Currency.wrap(address(USDL)),
            currency1: Currency.wrap(address(wUSDL)),
            fee: 0, // Must be 0 for wrapper pools
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        initSqrtPriceX96 = uint160(TickMath.getSqrtPriceAtTick(0));
        manager.initialize(poolKey, initSqrtPriceX96);

        // Give users some tokens
        USDL.mint(alice, 100 ether);
        USDL.mint(bob, 100 ether);
        USDL.mint(address(this), 200 ether);
        USDL.mint(address(wUSDL), 200 ether);

        wUSDL.mint(alice, 100 ether);
        wUSDL.mint(bob, 100 ether);
        wUSDL.mint(address(this), 200 ether);

        _addUnrelatedLiquidity();
    }

    function test_initialization() public view {
        assertEq(address(hook.wUSDL()), address(wUSDL));
        assertEq(Currency.unwrap(hook.wrapperCurrency()), address(wUSDL));
        assertEq(Currency.unwrap(hook.underlyingCurrency()), address(USDL));
    }

    function test_wrap_exactInput() public {
        uint256 wrapAmount = 1 ether;
        uint256 expectedOutput = wUSDL.previewDeposit(wrapAmount);

        vm.startPrank(alice);
        USDL.approve(address(swapRouter), type(uint256).max);

        uint256 aliceUsdlBefore = USDL.balanceOf(alice);
        uint256 aliceWusdlBefore = wUSDL.balanceOf(alice);
        uint256 managerUsdlBefore = USDL.balanceOf(address(manager));
        uint256 managerWusdlBefore = wUSDL.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
                            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, // USDL (0) to wUSDL (1)
                amountSpecified: -int256(wrapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(aliceUsdlBefore - USDL.balanceOf(alice), wrapAmount);
        assertEq(wUSDL.balanceOf(alice) - aliceWusdlBefore, expectedOutput);
        assertEq(managerUsdlBefore, USDL.balanceOf(address(manager)));
        assertEq(managerWusdlBefore, wUSDL.balanceOf(address(manager)));
    }

    function test_unwrap_exactInput() public {
        uint256 unwrapAmount = 1 ether;
        uint256 expectedOutput = wUSDL.previewRedeem(unwrapAmount);

        vm.startPrank(alice);
        wUSDL.approve(address(swapRouter), type(uint256).max);

        uint256 aliceUsdlBefore = USDL.balanceOf(alice);
        uint256 aliceWusdlBefore = wUSDL.balanceOf(alice);
        uint256 managerUsdlBefore = USDL.balanceOf(address(manager));
        uint256 managerWusdlBefore = wUSDL.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
                            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false, // wUSDL (1) to USDL (0)
                amountSpecified: -int256(unwrapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(USDL.balanceOf(alice) - aliceUsdlBefore, expectedOutput);
        assertEq(aliceWusdlBefore - wUSDL.balanceOf(alice), unwrapAmount);
        assertEq(managerUsdlBefore, USDL.balanceOf(address(manager)));
        assertEq(managerWusdlBefore, wUSDL.balanceOf(address(manager)));
    }

    function test_wrap_exactOutput() public {
        uint256 wrapAmount = 1 ether;
        uint256 expectedInput = wUSDL.previewMint(wrapAmount);

        vm.startPrank(alice);
        USDL.approve(address(swapRouter), type(uint256).max);

        uint256 aliceUsdlBefore = USDL.balanceOf(alice);
        uint256 aliceWusdlBefore = wUSDL.balanceOf(alice);
        uint256 managerUsdlBefore = USDL.balanceOf(address(manager));
        uint256 managerWusdlBefore = wUSDL.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
                            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: true, // USDL (0) to wUSDL (1)
                amountSpecified: int256(wrapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(aliceUsdlBefore - USDL.balanceOf(alice), expectedInput);
        assertEq(wUSDL.balanceOf(alice) - aliceWusdlBefore, wrapAmount);
        assertEq(managerUsdlBefore, USDL.balanceOf(address(manager)));
        assertEq(managerWusdlBefore, wUSDL.balanceOf(address(manager)));
    }

    function test_unwrap_exactOutput() public {
        uint256 unwrapAmount = 1 ether;
        uint256 expectedInput = wUSDL.previewWithdraw(unwrapAmount);

        vm.startPrank(alice);
        wUSDL.approve(address(swapRouter), type(uint256).max);

        uint256 aliceUsdlBefore = USDL.balanceOf(alice);
        uint256 aliceWusdlBefore = wUSDL.balanceOf(alice);
        uint256 managerUsdlBefore = USDL.balanceOf(address(manager));
        uint256 managerWusdlBefore = wUSDL.balanceOf(address(manager));

        PoolSwapTest.TestSettings memory testSettings =
                            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: false, // wUSDL (1) to USDL (0)
                amountSpecified: int256(unwrapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            testSettings,
            ""
        );

        vm.stopPrank();

        assertEq(USDL.balanceOf(alice) - aliceUsdlBefore, unwrapAmount);
        assertEq(aliceWusdlBefore - wUSDL.balanceOf(alice), expectedInput);
        assertEq(managerUsdlBefore, USDL.balanceOf(address(manager)));
        assertEq(managerWusdlBefore, wUSDL.balanceOf(address(manager)));
    }

    function test_revertAddLiquidity() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
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
        // Try to initialize with non-zero fee
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(USDL)),
            currency1: Currency.wrap(address(wUSDL)),
            fee: 3000, // Invalid: must be 0
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(BaseTokenWrapperHook.InvalidPoolFee.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(invalidKey, initSqrtPriceX96);

        // Try to initialize with wrong token pair
        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        // sort tokens
        (Currency currency0, Currency currency1) = address(randomToken) < address(wUSDL)
            ? (Currency.wrap(address(randomToken)), Currency.wrap(address(wUSDL)))
            : (Currency.wrap(address(wUSDL)), Currency.wrap(address(randomToken)));
        invalidKey =
                        PoolKey({currency0: currency0, currency1: currency1, fee: 0, tickSpacing: 60, hooks: IHooks(address(hook))});

        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(BaseTokenWrapperHook.InvalidPoolToken.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        manager.initialize(invalidKey, initSqrtPriceX96);
    }

    function _addUnrelatedLiquidity() internal {
        // Create a hookless pool key for USDL/wUSDL
        PoolKey memory unrelatedPoolKey = PoolKey({
            currency0: Currency.wrap(address(USDL)),
            currency1: Currency.wrap(address(wUSDL)),
            fee: 100,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        manager.initialize(unrelatedPoolKey, uint160(TickMath.getSqrtPriceAtTick(0)));

        USDL.approve(address(modifyLiquidityRouter), type(uint256).max);
        wUSDL.approve(address(modifyLiquidityRouter), type(uint256).max);
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