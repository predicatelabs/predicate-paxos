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
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {PredicateHook} from "../../src/PredicateHook.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
/// @notice Forge script for deploying v4 & hooks

contract DeployTokensAndPool is Script, DeployPermit2 {
    using EasyPosm for IPositionManager;

    INetwork private _env;
    address private _hookAddress;
    V4Router private _swapRouter;

    address public admin;
    address public supplyController;
    address public pauser;
    address public assetProtector;
    address public rebaser;
    address public rebaserAdmin;

    YBSV1_1 public USDL;
    wYBSV1 public wUSDL;
    MockERC20 public USDC;
    IPositionManager public posm;
    PoolModifyLiquidityTest public lpRouter;
    IPoolManager public manager;

    uint256 public amount0Max = 100e18;
    uint256 public amount1Max = 100e6;

    uint256 public initialSupply = 1000e18; // 1000 tokens

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
        _swapRouter = V4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));

        admin = msg.sender;
        supplyController = msg.sender;
        pauser = msg.sender;
        assetProtector = msg.sender;
        rebaser = msg.sender;
        rebaserAdmin = msg.sender;
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();

        vm.startBroadcast();
        manager = config.poolManager;
        _deployPosm();
        _deployRouters();
        console.log("Deployed POSM: %s", address(posm));
        console.log("Deployed LP Router: %s", address(lpRouter));
        vm.stopBroadcast();

        vm.startBroadcast();
        PredicateHook predicateHook = PredicateHook(_hookAddress);
        address[] memory _lps = new address[](2);
        _lps[0] = address(posm);
        _lps[1] = address(lpRouter);
        predicateHook.addAuthorizedLPs(_lps);
        _initializePool();
        vm.stopBroadcast();
    }

    // -----------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------

    function _deployRouters() internal {
        lpRouter = new PoolModifyLiquidityTest(manager);
    }

    function _deployPosm() internal {
        anvilPermit2();
        posm = IPositionManager(
            new PositionManager(manager, permit2, 300_000, IPositionDescriptor(address(0)), IWETH9(address(0)))
        );
    }

    function _approvePosmCurrency(
        Currency currency
    ) internal {
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);
        permit2.approve(Currency.unwrap(currency), address(posm), type(uint160).max, type(uint48).max);
    }

    function _initializePool() internal {
        // deploy tokens
        for (uint256 i = 0; i < 100; i++) {
            _setUpUSDL();
            if (_addressStartsWithB(address(USDL))) {
                break;
            }
        }
        require(_addressStartsWithB(address(USDL)), "USDL address does not start with B");

        for (uint256 i = 0; i < 100; i++) {
            _setUpVault();
            if (_addressStartsWith7(address(wUSDL))) {
                break;
            }
        }
        require(_addressStartsWith7(address(wUSDL)), "wUSDL address does not start with 7");

        for (uint256 i = 0; i < 10; i++) {
            USDC = _deployAndMintToken(msg.sender, 100_000_000_000_000);
            if (_addressStartsWithA(address(USDC))) {
                break;
            }
        }

        console.log("USDC address: %s", address(USDC));
        console.log("wUSDL address: %s", address(wUSDL));
        console.log("USDL address: %s", address(USDL));

        // Deploy liquidity pool with predicate hook
        int24 tickSpacing = 60;
        PoolKey memory poolKey =
            PoolKey(Currency.wrap(address(wUSDL)), Currency.wrap(address(USDC)), 0, tickSpacing, IHooks(_hookAddress));
        uint160 predicatePoolStartingPrice = 79_228_162_514_264_337_593_543;

        manager.initialize(poolKey, predicatePoolStartingPrice);

        // Approve tokens for liquidity router and swap router
        IERC20(address(wUSDL)).approve(address(lpRouter), type(uint256).max);
        IERC20(address(USDC)).approve(address(lpRouter), type(uint256).max);
        IERC20(address(wUSDL)).approve(address(_swapRouter), type(uint256).max);
        IERC20(address(USDC)).approve(address(_swapRouter), type(uint256).max);
        _approvePosmCurrency(Currency.wrap(address(wUSDL)));
        _approvePosmCurrency(Currency.wrap(address(USDC)));

        // increase supply of USDL
        USDL.increaseSupply(initialSupply * 7);
        USDL.transfer(msg.sender, initialSupply * 6);

        // Approve and deposit USDL for wUSDL
        IERC20Upgradeable(address(USDL)).approve(address(wUSDL), type(uint256).max);
        wUSDL.deposit(4 * initialSupply, msg.sender);

        // Provision liquidity
        _provisionLiquidity(predicatePoolStartingPrice, tickSpacing, poolKey, msg.sender);
    }

    function _setUpUSDL() internal {
        YBSV1_1 ybsImpl = new YBSV1_1();

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

        USDL.setMaxRebaseRate(0.05 * 10 ** 18); // 5% max rate
        USDL.setRebasePeriod(1 days);
    }

    function _setUpVault() internal {
        wYBSV1 wYbsImpl = new wYBSV1();
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
        USDL.grantRole(USDL.WRAPPED_YBS_ROLE(), address(wUSDL));
    }

    function _deployAndMintToken(address sender, uint256 amount) internal returns (MockERC20 token) {
        token = _deployToken();
        token.mint(sender, amount);
        return token;
    }

    function _deployToken() internal returns (MockERC20 token) {
        token = new MockERC20("MockToken", "MT", 6);
    }

    function _provisionLiquidity(
        uint160 sqrtPriceX96,
        int24 tickSpacing,
        PoolKey memory poolKey,
        address sender
    ) internal {
        bytes memory ZERO_BYTES = new bytes(0);

        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        int24 tickLower = (currentTick - 600) - ((currentTick - 600) % tickSpacing);
        int24 tickUpper = (currentTick + 600) - ((currentTick + 600) % tickSpacing);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Max,
            amount1Max
        );

        posm.mint(
            poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, sender, block.timestamp + 300, ZERO_BYTES
        );
    }

    function _addressStartsWith7(
        address _addr
    ) internal pure returns (bool) {
        uint256 addrValue = uint256(uint160(_addr));
        uint256 topNibble = (addrValue >> 156) & 0xF; // isolate bits 159..156
        return topNibble == 0x7;
    }

    function _addressStartsWithB(
        address _addr
    ) internal pure returns (bool) {
        uint256 addrValue = uint256(uint160(_addr));
        uint256 topNibble = (addrValue >> 156) & 0xF;
        return topNibble == 0xB;
    }

    function _addressStartsWithA(
        address _addr
    ) internal pure returns (bool) {
        uint256 addrValue = uint256(uint160(_addr));
        uint256 topNibble = (addrValue >> 156) & 0xF;
        return topNibble == 0xA;
    }
}
