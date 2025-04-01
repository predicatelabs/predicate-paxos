// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {YBSV1_1} from "../../src/paxos/YBSV1_1.sol";
import {wYBSV1} from "../../src/paxos/wYBSV1.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Constants} from "@uniswap/v4-core/src/../test/utils/Constants.sol";
import {MetaCoinTestSetup} from "@predicate-test/helpers/utility/MetaCoinTestSetup.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {PoolSetup} from "./PoolSetup.sol";

contract AutoWrapperSetup is MetaCoinTestSetup, PoolSetup {
    PredicateHook public predicateHook;
    AutoWrapper public autoWrapper;
    YBSV1_1 public USDL;
    wYBSV1 public wUSDL;
    Currency public USDC;
    PoolKey public predicatePoolKey;
    PoolKey public ghostPoolKey;
    uint160 public initSqrtPriceX96;

    address public admin;
    address public supplyController;
    address public pauser;
    address public assetProtector;
    address public rebaserAdmin;
    address public rebaser;
    address public alice;

    uint256 public initialSupply = 1000 * 10 ** 18; // 1000 tokens
    int24 public tickSpacing = 60;

    function _setUpHooksAndPools(
        address _liquidityProvider
    ) internal {
        // deploy pool manager, routers and posm

        admin = makeAddr("admin");
        supplyController = makeAddr("supplyController");
        pauser = makeAddr("pauser");
        assetProtector = makeAddr("assetProtector");
        rebaserAdmin = makeAddr("rebaserAdmin");
        rebaser = makeAddr("rebaser");
        alice = makeAddr("alice");

        _deployPoolManager();
        _deployRouters();
        _deployPosm();

        // deploy tokens
        _setupUSDLandVault();
        USDC = _deployAndMintToken(_liquidityProvider, 100_000_000 ether);

        // set approvals
        vm.startPrank(_liquidityProvider);
        _setTokenApprovalForRouters(USDC);
        _setTokenApprovalForRouters(Currency.wrap(address(USDL)));
        _setTokenApprovalForRouters(Currency.wrap(address(wUSDL)));
        vm.stopPrank();

        // create hook here
        uint160 predicateHookFlags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG);
        bytes memory constructorArgs = abi.encode(manager, swapRouter, address(serviceManager), "testPolicy", admin);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), predicateHookFlags, type(PredicateHook).creationCode, constructorArgs);

        predicateHook = new PredicateHook{salt: salt}(manager, swapRouter, address(serviceManager), "testPolicy", admin);
        require(address(predicateHook) == hookAddress, "Hook deployment failed");

        // initialize the pool
        predicatePoolKey = PoolKey(USDC, Currency.wrap(address(wUSDL)), 0, tickSpacing, IHooks(predicateHook));
        manager.initialize(predicatePoolKey, Constants.SQRT_PRICE_1_1);

        // initialize the auto wrapper
        uint160 autoWrapperFlags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory autoWrapperConstructorArgs =
            abi.encode(manager, ERC4626(address(wUSDL)), USDC, predicatePoolKey, swapRouter);
        (address autoWrapperAddress, bytes32 autoWrapperSalt) =
            HookMiner.find(address(this), autoWrapperFlags, type(AutoWrapper).creationCode, autoWrapperConstructorArgs);
        autoWrapper =
            new AutoWrapper{salt: autoWrapperSalt}(manager, ERC4626(address(wUSDL)), USDC, predicatePoolKey, swapRouter);
        require(address(autoWrapper) == autoWrapperAddress, "Hook deployment failed");

        // initialize the ghost pool
        ghostPoolKey = PoolKey(USDC, Currency.wrap(address(USDL)), 0, tickSpacing, IHooks(autoWrapper));
        manager.initialize(ghostPoolKey, Constants.SQRT_PRICE_1_1);

        // Create initial supply of USDL
        vm.startPrank(supplyController);
        USDL.increaseSupply(initialSupply * 7);
        USDL.transfer(_liquidityProvider, initialSupply * 6);
        vm.stopPrank();

        // Approve and deposit USDL for wUSDL
        vm.startPrank(_liquidityProvider);
        IERC20Upgradeable(address(USDL)).approve(address(wUSDL), type(uint256).max);
        IERC20(address(USDL)).approve(address(autoWrapper), type(uint256).max);
        IERC20(Currency.unwrap(USDC)).approve(address(autoWrapper), type(uint256).max);
        IERC20Upgradeable(address(wUSDL)).approve(address(autoWrapper), type(uint256).max);
        wUSDL.deposit(3 * initialSupply, _liquidityProvider);
        vm.stopPrank();

        // provision liquidity
        vm.startPrank(admin);
        address[] memory authorizedLps = new address[](3);
        authorizedLps[0] = _liquidityProvider;
        predicateHook.addAuthorizedLPs(authorizedLps);

        require(predicateHook.isAuthorizedLP(_liquidityProvider), "Liquidity Provider not authorized");
        vm.stopPrank();

        vm.startPrank(_liquidityProvider);
        _provisionLiquidity(tickSpacing, predicatePoolKey, 100 ether, _liquidityProvider, 100_000 ether, 100_000 ether);
        vm.stopPrank();
    }

    function _setupUSDLandVault() internal {
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

        vm.startPrank(rebaserAdmin);
        USDL.setMaxRebaseRate(0.05 * 10 ** 18); // 5% max rate
        USDL.setRebasePeriod(1 days);
        vm.stopPrank();

        vm.startPrank(admin);
        USDL.grantRole(USDL.WRAPPED_YBS_ROLE(), address(wUSDL));
        vm.stopPrank();
    }

    function getPredicatePoolKey() public view returns (PoolKey memory) {
        return predicatePoolKey;
    }

    function getPoolKey() public view returns (PoolKey memory) {
        return ghostPoolKey;
    }

    function getTickSpacing() public view returns (int24) {
        return tickSpacing;
    }
}
