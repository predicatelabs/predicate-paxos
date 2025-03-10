// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
// import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
// import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
// import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
// import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
// import {Test} from "forge-std/Test.sol";

// import {AutoWrapper} from "../src/AutoWrapper.sol";
// import {YBSV1_1} from "../src/paxos/YBSV1_1.sol";
// import {wYBSV1} from "../src/paxos/wYBSV1.sol";

// contract AutoWrapperTest is Test, Deployers {
//     using PoolIdLibrary for PoolKey;
//     using CurrencyLibrary for Currency;

//     AutoWrapper public hook;
//     YBSV1_1 public USDL;
//     wYBSV1 public wUSDL;
//     PoolKey poolKey;
//     uint160 initSqrtPriceX96;

//     address admin;
//     address supplyController;
//     address pauser;
//     address assetProtector;
//     address rebaserAdmin;
//     address rebaser;
//     address alice;

//     uint256 public initialSupply = 1000 * 10 ** 18; // 1000 tokens

//     event Transfer(address indexed from, address indexed to, uint256 amount);

//     function setUp() public {
//         admin = makeAddr("admin");
//         supplyController = makeAddr("supplyController");
//         pauser = makeAddr("pauser");
//         assetProtector = makeAddr("assetProtector");
//         rebaserAdmin = makeAddr("rebaserAdmin");
//         rebaser = makeAddr("rebaser");
//         alice = makeAddr("alice");
//         deployFreshManagerAndRouters();
//         setupUSDLandVault();

//         hook = AutoWrapper(
//             payable(
//                 address(
//                     uint160(
//                         (type(uint160).max & clearAllHookPermissionsMask) | Hooks.BEFORE_SWAP_FLAG
//                             | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
//                             | Hooks.BEFORE_INITIALIZE_FLAG
//                     )
//                 )
//             )
//         );
//         deployCodeTo("AutoWrapper", abi.encode(manager, wUSDL), address(hook));

//         poolKey = PoolKey({
//             currency0: Currency.wrap(address(USDL)),
//             currency1: Currency.wrap(address(wUSDL)),
//             fee: 0,
//             tickSpacing: 60,
//             hooks: IHooks(address(hook))
//         });

//         initSqrtPriceX96 = uint160(TickMath.getSqrtPriceAtTick(0));
//         manager.initialize(poolKey, initSqrtPriceX96);

//         vm.startPrank(supplyController);
//         USDL.increaseSupply(initialSupply * 4);
//         USDL.transfer(alice, initialSupply);
//         USDL.transfer(address(this), initialSupply * 2);
//         vm.stopPrank();

//         IERC20Upgradeable(address(USDL)).approve(address(wUSDL), initialSupply);
//         wUSDL.deposit(initialSupply, address(this));

//         _addUnrelatedLiquidity();
//     }

//     function setupUSDLandVault() internal {
//         YBSV1_1 ybsImpl = new YBSV1_1();
//         wYBSV1 wYbsImpl = new wYBSV1();

//         bytes memory ybsData = abi.encodeWithSelector(
//             YBSV1_1.initialize.selector,
//             "Yield Bearing Stablecoin",
//             "YBS",
//             18,
//             admin,
//             supplyController,
//             pauser,
//             assetProtector,
//             rebaserAdmin,
//             rebaser
//         );

//         ERC1967Proxy ybsProxy = new ERC1967Proxy(address(ybsImpl), ybsData);
//         USDL = YBSV1_1(address(ybsProxy));

//         bytes memory wYbsData = abi.encodeWithSelector(
//             wYBSV1.initialize.selector,
//             "Wrapped YBS",
//             "wYBS",
//             IERC20Upgradeable(address(USDL)),
//             admin,
//             pauser,
//             assetProtector
//         );

//         ERC1967Proxy wYbsProxy = new ERC1967Proxy(address(wYbsImpl), wYbsData);
//         wUSDL = wYBSV1(address(wYbsProxy));

//         vm.startPrank(rebaserAdmin);
//         USDL.setMaxRebaseRate(0.05 * 10 ** 18); // 5% max rate
//         USDL.setRebasePeriod(1 days);
//         vm.stopPrank();

//         vm.startPrank(admin);
//         USDL.grantRole(USDL.WRAPPED_YBS_ROLE(), address(wUSDL));
//         vm.stopPrank();
//     }

//     function test_initialization() public view {
//         assertEq(address(hook.vault()), address(wUSDL));
//         assertEq(Currency.unwrap(hook.wrapperCurrency()), address(wUSDL));
//         assertEq(Currency.unwrap(hook.underlyingCurrency()), address(USDL));
//     }

//     function test_wrap_exactInput() public {
//         uint256 wrapAmount = 1 ether;
//         uint256 expectedOutput = wUSDL.previewDeposit(wrapAmount);

//         vm.startPrank(alice);
//         IERC20Upgradeable(address(USDL)).approve(address(swapRouter), type(uint256).max);

//         uint256 aliceYbsBefore = USDL.balanceOf(alice);
//         uint256 aliceWYbsBefore = wUSDL.balanceOf(alice);
//         uint256 managerYbsBefore = USDL.balanceOf(address(manager));
//         uint256 managerWYbsBefore = wUSDL.balanceOf(address(manager));

//         PoolSwapTest.TestSettings memory testSettings =
//             PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
//         swapRouter.swap(
//             poolKey,
//             IPoolManager.SwapParams({
//                 zeroForOne: true, // ybs (0) to wYbs (1)
//                 amountSpecified: -int256(wrapAmount),
//                 sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
//             }),
//             testSettings,
//             ""
//         );

//         vm.stopPrank();

//         assertEq(aliceYbsBefore - USDL.balanceOf(alice), wrapAmount);
//         assertEq(wUSDL.balanceOf(alice) - aliceWYbsBefore, expectedOutput);
//         assertEq(managerYbsBefore, USDL.balanceOf(address(manager)));
//         assertEq(managerWYbsBefore, wUSDL.balanceOf(address(manager)));
//     }

//     function test_unwrap_exactInput() public {
//         vm.startPrank(alice);
//         IERC20Upgradeable(address(USDL)).approve(address(wUSDL), 10 ether);
//         wUSDL.deposit(10 ether, alice);

//         uint256 unwrapAmount = 1 ether;
//         uint256 expectedOutput = wUSDL.previewRedeem(unwrapAmount);

//         IERC20Upgradeable(address(wUSDL)).approve(address(swapRouter), type(uint256).max);

//         uint256 aliceYbsBefore = USDL.balanceOf(alice);
//         uint256 aliceWYbsBefore = wUSDL.balanceOf(alice);
//         uint256 managerYbsBefore = USDL.balanceOf(address(manager));
//         uint256 managerWYbsBefore = wUSDL.balanceOf(address(manager));

//         PoolSwapTest.TestSettings memory testSettings =
//             PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
//         swapRouter.swap(
//             poolKey,
//             IPoolManager.SwapParams({
//                 zeroForOne: false, // wYbs (1) to ybs (0)
//                 amountSpecified: -int256(unwrapAmount),
//                 sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
//             }),
//             testSettings,
//             ""
//         );

//         vm.stopPrank();

//         assertEq(aliceWYbsBefore - wUSDL.balanceOf(alice), unwrapAmount);
//         assertEq(USDL.balanceOf(alice) - aliceYbsBefore, expectedOutput);
//         assertEq(managerYbsBefore, USDL.balanceOf(address(manager)));
//         assertEq(managerWYbsBefore, wUSDL.balanceOf(address(manager)));
//     }

//     function _addUnrelatedLiquidity() internal {
//         // Create a hookless pool key for ybs/wYbs
//         PoolKey memory unrelatedPoolKey = PoolKey({
//             currency0: Currency.wrap(address(USDL)),
//             currency1: Currency.wrap(address(wUSDL)),
//             fee: 100,
//             tickSpacing: 60,
//             hooks: IHooks(address(0))
//         });

//         manager.initialize(unrelatedPoolKey, uint160(TickMath.getSqrtPriceAtTick(0)));

//         IERC20Upgradeable(address(USDL)).approve(address(modifyLiquidityRouter), type(uint256).max);
//         IERC20Upgradeable(address(wUSDL)).approve(address(modifyLiquidityRouter), type(uint256).max);
//         modifyLiquidityRouter.modifyLiquidity(
//             unrelatedPoolKey,
//             IPoolManager.ModifyLiquidityParams({
//                 tickLower: -120,
//                 tickUpper: 120,
//                 liquidityDelta: 1000e18,
//                 salt: bytes32(0)
//             }),
//             ""
//         );
//     }
// }
