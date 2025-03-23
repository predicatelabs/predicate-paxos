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
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {YBSV1_1} from "../../src/paxos/YBSV1_1.sol";
import {wYBSV1} from "../../src/paxos/wYBSV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {PredicateHook} from "../../src/PredicateHook.sol";

/// @notice Forge script for deploying v4 & hooks
contract DeployTokensAndPool is Script, DeployPermit2 {
    using EasyPosm for IPositionManager;

    INetwork private _env;
    address private hookAddress;
    ISimpleV4Router private swapRouter;

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
        hookAddress = vm.envAddress("HOOK_ADDRESS");
        swapRouter = ISimpleV4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();

        vm.startBroadcast();
        IPoolManager manager = config.poolManager;
        IPositionManager posm = deployPosm(manager);
        PoolModifyLiquidityTest lpRouter = deployRouters(manager);
        console.log("Deployed POSM: %s", address(posm));
        console.log("Deployed LP Router: %s", address(lpRouter));
        vm.stopBroadcast();

        vm.startBroadcast();
        PredicateHook predicateHook = PredicateHook(hookAddress);
        address[] memory _lps = new address[](2);
        _lps[0] = address(posm);
        _lps[1] = address(lpRouter);
        predicateHook.addAuthorizedLPs(_lps);
        initializePool(manager, hookAddress, posm, lpRouter, swapRouter);
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
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }

    function initializePool(
        IPoolManager manager,
        address hook,
        IPositionManager posm,
        PoolModifyLiquidityTest lpRouter,
        ISimpleV4Router swapRouter
    ) internal {
        (YBSV1_1 USDL, wYBSV1 wUSDL, MockERC20 baseToken) = setupTokens();
        logTokens(address(USDL), address(wUSDL), address(baseToken));

        Currency token0;
        Currency token1;
        if (uint160(address(baseToken)) < uint160(address(wUSDL))) {
            token0 = Currency.wrap(address(baseToken));
            token1 = Currency.wrap(address(wUSDL));
        } else {
            token0 = Currency.wrap(address(wUSDL));
            token1 = Currency.wrap(address(baseToken));
        }

        console.log(
            "Deploying liquidity pool with token0: %s and token1: %s", Currency.unwrap(token0), Currency.unwrap(token1)
        );

        // Deploy liquidity pool with predicate hook
        bytes memory ZERO_BYTES = new bytes(0);
        int24 tickSpacing = 60;
        PoolKey memory poolKey = PoolKey(token0, token1, 0, tickSpacing, IHooks(hook));
        manager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Approve tokens for liquidity router and swap router
        IERC20(Currency.unwrap(token0)).approve(address(lpRouter), type(uint256).max);
        IERC20(Currency.unwrap(token1)).approve(address(lpRouter), type(uint256).max);
        IERC20(Currency.unwrap(token0)).approve(address(swapRouter), type(uint256).max);
        IERC20(Currency.unwrap(token1)).approve(address(swapRouter), type(uint256).max);

        approvePosmCurrency(posm, token0);
        approvePosmCurrency(posm, token1);

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

    /*
    * @notice Deploy YBSV1_1, wYBSV1 and baseToken
    * @dev This function is used to deploy the YBSV1_1, wYBSV1 and baseToken
    * @dev also mints and approves tokens for the deployer for baseToken
    * @dev sets defaults and ensures token is ready for use in a pool
    * @dev also sets approvals for autoWrapper, wUSDL and baseToken
    */
    function setupTokens() internal returns (YBSV1_1 USDL, wYBSV1 wUSDL, MockERC20 baseToken) {
        address admin = msg.sender;
        address supplyController = msg.sender;
        address pauser = msg.sender;
        address assetProtector = msg.sender;
        address rebaser = msg.sender;
        address rebaserAdmin = msg.sender;

        uint256 initialSupply = 1000 * 10 ** 18; // 1000 token

        YBSV1_1 ybsImpl = new YBSV1_1();
        wYBSV1 wYbsImpl = new wYBSV1();

        bytes memory ybsData = abi.encodeWithSelector(
            YBSV1_1.initialize.selector,
            "Yield Bearing Stablecoin",
            "YBS",
            18,
            admin,
            supplyController,
            pauser,
            assetProtector,
            rebaserAdmin,
            rebaser
        );

        ERC1967Proxy ybsProxy = new ERC1967Proxy(address(ybsImpl), ybsData);
        USDL = YBSV1_1(address(ybsProxy));

        bytes memory wYbsData = abi.encodeWithSelector(
            wYBSV1.initialize.selector,
            "Wrapped YBS",
            "wYBS",
            IERC20Upgradeable(address(USDL)),
            admin,
            pauser,
            assetProtector
        );

        ERC1967Proxy wYbsProxy = new ERC1967Proxy(address(wYbsImpl), wYbsData);
        wUSDL = wYBSV1(address(wYbsProxy));

        // Deploy baseCurrency for pool
        baseToken = new MockERC20("MockA", "A", 18); // USDC
        // Mint 100_000 ether to msg.sender
        baseToken.mint(msg.sender, 100_000 ether);

        // Set max rebase rate to 5%
        USDL.setMaxRebaseRate(0.05 * 10 ** 18);

        // Set rebase period to 1 day
        USDL.setRebasePeriod(1 days);

        // Grant wrapped ybs role to wUSDL
        USDL.grantRole(USDL.WRAPPED_YBS_ROLE(), address(wUSDL));

        // Mint 7 * initialSupply of USDL to msg.sender
        USDL.increaseSupply(initialSupply * 7);
        // Transfer 6 * initialSupply of USDL to msg.sender
        USDL.transfer(msg.sender, initialSupply * 6);
        // Approve wUSDL to deposit USDL from msg.sender
        IERC20Upgradeable(address(USDL)).approve(address(wUSDL), type(uint256).max);
        // Deposit 3 * initialSupply of USDL from msg.sender to wUSDL
        wUSDL.deposit(3 * initialSupply, msg.sender);

        return (USDL, wUSDL, baseToken);
    }

    function logTokens(address USDL, address wUSDL, address baseToken) internal {
        console.log("Deployed YBSV1_1: %s", address(USDL));
        console.log("Deployed wYBSV1: %s", address(wUSDL));
        console.log("Deployed baseToken: %s", address(baseToken));

        if (uint160(address(USDL)) < uint160(address(baseToken))) {
            console.log("USDL is less than baseToken; it will be USDL/baseToken pool");
        } else {
            console.log("USDL is greater than baseToken; it will be baseToken/USDL pool");
        }

        if (uint160(address(wUSDL)) < uint160(address(baseToken))) {
            console.log("wUSDL is less than baseToken; it will be wUSDL/baseToken pool");
        } else {
            console.log("wUSDL is greater than baseToken; it will be baseToken/wUSDL pool");
        }
    }
}
