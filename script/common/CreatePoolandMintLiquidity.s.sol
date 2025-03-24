// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {PredicateHook} from "../../src/PredicateHook.sol";

contract CreatePoolAndAddLiquidityScript is Script {
    using CurrencyLibrary for Currency;

    Currency private currency0;
    Currency private currency1;

    PositionManager private posm;
    IAllowanceTransfer private permit2;
    ISimpleV4Router private swapRouter;

    INetwork private _env;
    address private hookAddress;

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

    /////////////////////////////////////

    function run() external {
        _init();
        INetwork.Config memory config = _env.config();
        INetwork.LiquidityPoolConfig memory poolConfig = _env.liquidityPoolConfig();

        // --------------------------------- //
        posm = config.positionManager;
        permit2 = config.permit2;
        currency0 = Currency.wrap(poolConfig.token0);
        currency1 = Currency.wrap(poolConfig.token1);

        // tokens should be sorted
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: poolConfig.fee,
            tickSpacing: poolConfig.tickSpacing,
            hooks: IHooks(hookAddress)
        });
        bytes memory hookData = new bytes(0);

        // --------------------------------- //

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            poolConfig.startingPrice,
            TickMath.getSqrtPriceAtTick(poolConfig.tickLower),
            TickMath.getSqrtPriceAtTick(poolConfig.tickUpper),
            poolConfig.token0Amount,
            poolConfig.token1Amount
        );

        // slippage limits
        uint256 amount0Max = poolConfig.token0Amount + 1 wei;
        uint256 amount1Max = poolConfig.token1Amount + 1 wei;

        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            pool, poolConfig.tickLower, poolConfig.tickUpper, liquidity, amount0Max, amount1Max, address(this), hookData
        );

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // initialize pool
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, poolConfig.startingPrice, hookData);

        // mint liquidity
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        // add authorized LPs
        address[] memory authorizedLps = new address[](1);
        authorizedLps[0] = address(posm);
        PredicateHook predicateHook = PredicateHook(hookAddress);

        // approve tokens and mint liquidity
        vm.startBroadcast();
        predicateHook.addAuthorizedLPs(authorizedLps);
        _tokenApprovals();
        posm.multicall(params);
        vm.stopBroadcast();
    }

    /// @dev helper function for encoding mint liquidity operation
    /// @dev does NOT encode SWEEP, developers should take care when minting liquidity on an ETH pair
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }

    function _tokenApprovals() internal {
        require(!currency0.isAddressZero() && !currency1.isAddressZero(), "Currency must not be zero");

        IERC20 token0 = IERC20(Currency.unwrap(currency0));
        IERC20 token1 = IERC20(Currency.unwrap(currency1));

        // approve token0
        token0.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
        token0.approve(address(swapRouter), type(uint256).max);

        // approve token1
        token1.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token1), address(posm), type(uint160).max, type(uint48).max);
        token1.approve(address(swapRouter), type(uint256).max);
    }
}
