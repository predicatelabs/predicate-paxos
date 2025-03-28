// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
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
import {console} from "forge-std/console.sol";
import {PoolSetup} from "./PoolSetup.sol";

contract AutoWrapperSetup is MetaCoinTestSetup, PoolSetup {
    PredicateHook public predicateHook;
    AutoWrapper public autoWrapper;
    YBSV1_1 public USDL;
    wYBSV1 public wUSDL;
    Currency public USDC;
    PoolKey predicatePoolKey;
    PoolKey ghostPoolKey;
    uint160 initSqrtPriceX96;

    address admin;
    address supplyController;
    address pauser;
    address assetProtector;
    address rebaserAdmin;
    address rebaser;
    address alice;

    uint256 public initialSupply = 1000e18; // 1000 token
    int24 tickSpacing = 60;

    uint160 predicatePoolStartingPrice = 79_228_162_514_264_337_593_543;
    uint160 ghostPoolStartingPrice = 79_228_162_514_264_337_593_543_950_336_000_000;

    function setUpHooksAndPools(
        address liquidityProvider
    ) internal {
        // deploy pool manager, routers and posm

        admin = makeAddr("admin");
        supplyController = makeAddr("supplyController");
        pauser = makeAddr("pauser");
        assetProtector = makeAddr("assetProtector");
        rebaserAdmin = makeAddr("rebaserAdmin");
        rebaser = makeAddr("rebaser");
        alice = makeAddr("alice");

        deployPoolManager();
        deployRouters();
        deployPosm();

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
            USDC = deployAndMintToken(liquidityProvider, 100_000_000_000_000);
            if (_addressStartsWithA(Currency.unwrap(USDC))) {
                break;
            }
        }
        require(_addressStartsWithA(Currency.unwrap(USDC)), "USDC address does not start with A");

        // set approvals
        vm.startPrank(liquidityProvider);
        setTokenApprovalForRouters(USDC);
        setTokenApprovalForRouters(Currency.wrap(address(USDL)));
        setTokenApprovalForRouters(Currency.wrap(address(wUSDL)));
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
        predicatePoolKey = PoolKey(Currency.wrap(address(wUSDL)), USDC, 0, tickSpacing, IHooks(predicateHook));
        manager.initialize(predicatePoolKey, predicatePoolStartingPrice);

        // initialize the auto wrapper
        uint160 autoWrapperFlags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
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
        manager.initialize(ghostPoolKey, ghostPoolStartingPrice);

        // Create initial supply of USDL
        vm.startPrank(supplyController);
        USDL.increaseSupply(initialSupply * 7);
        USDL.transfer(liquidityProvider, initialSupply * 6);
        vm.stopPrank();

        // Approve and deposit USDL for wUSDL
        vm.startPrank(liquidityProvider);
        IERC20Upgradeable(address(USDL)).approve(address(wUSDL), type(uint256).max);
        IERC20(address(USDL)).approve(address(autoWrapper), type(uint256).max);
        IERC20(Currency.unwrap(USDC)).approve(address(autoWrapper), type(uint256).max);
        IERC20Upgradeable(address(wUSDL)).approve(address(autoWrapper), type(uint256).max);
        wUSDL.deposit(4 * initialSupply, liquidityProvider);
        vm.stopPrank();

        // provision liquidity
        vm.startPrank(admin);
        address[] memory authorizedLps = new address[](1);
        authorizedLps[0] = address(posm);
        predicateHook.addAuthorizedLPs(authorizedLps);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        _provisionLiquidity(predicatePoolStartingPrice, tickSpacing, predicatePoolKey, liquidityProvider, 100e18, 100e6);
        vm.stopPrank();
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

        vm.startPrank(rebaserAdmin);
        USDL.setMaxRebaseRate(0.05 * 10 ** 18); // 5% max rate
        USDL.setRebasePeriod(1 days);
        vm.stopPrank();
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
