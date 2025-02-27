// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {PredicateHook} from "../../src/PredicateHook.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {wYBSV1} from "../../src/paxos/wYBSV1.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TestWrapperSetup {
    PredicateHook public hook;
    IPoolManager public poolManager;
    ISimpleV4Router public router;
    AutoWrapper public wrapper;
    MockERC20 public ybs;
    wYBSV1 public wYBS;
    MockERC20 public usdc;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function setUpHook() internal {
        poolManager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);
    }

    function setUp() public virtual {
        setUpHook();

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

        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG);
        bytes memory constructorArgs = abi.encode(poolManager, address(ybs), poolKey);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(AutoWrapper).creationCode, constructorArgs);

        wrapper = new AutoWrapper{salt: salt}(poolManager, address(ybs), poolKey);
        require(address(wrapper) == hookAddress, "AutoWrapper deployed at wrong address");

        ybs.mint(address(this), 1000e18);
        usdc.mint(address(this), 1000e6);
    }
}
