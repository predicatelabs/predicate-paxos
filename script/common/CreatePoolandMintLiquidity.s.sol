// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {PredicateHook} from "../../src/PredicateHook.sol";

contract CreatePoolAndMintLiquidity is Script {
    using CurrencyLibrary for Currency;

    Currency private _currency0;
    Currency private _currency1;
    PositionManager private _posm;
    IAllowanceTransfer private _permit2;

    INetwork private _env;
    address private _hookAddress;
    V4Router private _swapRouter;

    uint256 public wUSDLAmount = 100e18;
    uint256 public USDCAmount = 100e6;
    uint160 public startingPrice = 79_228_162_514_264_337_593_543;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        bool hookAddressExists = vm.envExists("HOOK_ADDRESS");
        bool swapRouterAddressExists = vm.envExists("SWAP_ROUTER_ADDRESS");
        require(
            networkExists && hookAddressExists && swapRouterAddressExists,
            "All environment variables must be set if any are specified"
        );
        string memory _network = vm.envString("NETWORK");
        _env = new NetworkSelector().select(_network);
        _hookAddress = vm.envAddress("HOOK_ADDRESS");
        _swapRouter = V4Router(vm.envAddress("SWAP_ROUTER_ADDRESS"));
    }

    /////////////////////////////////////

    function run() external {
        _init();
        INetwork.Config memory config = _env.config();
        INetwork.TokenConfig memory tokenConfig = _env.tokenConfig();

        // --------------------------------- //
        _posm = config.positionManager;
        _permit2 = config.permit2;
        _currency0 = tokenConfig.wUSDL;
        _currency1 = tokenConfig.USDC;

        // tokens should be sorted
        PoolKey memory pool = PoolKey({
            currency0: _currency0,
            currency1: _currency1,
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(_hookAddress)
        });
        bytes memory hookData = new bytes(0);

        // --------------------------------- //

        // Get tick at current price
        int24 currentTick = TickMath.getTickAtSqrtPrice(startingPrice);
        console.log("Current tick: %s", currentTick);
        // Ensure ticks are aligned with tick spacing
        int24 tickSpacing = 60;
        int24 tickLower = (currentTick - 600) - ((currentTick - 600) % tickSpacing);
        int24 tickUpper = (currentTick + 600) - ((currentTick + 600) % tickSpacing);

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            wUSDLAmount,
            USDCAmount
        );

        // slippage limits
        uint256 amount0Max = wUSDLAmount + 100 wei;
        uint256 amount1Max = USDCAmount + 100 wei;

        (bytes memory actions, bytes[] memory mintParams) =
            _mintLiquidityParams(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, msg.sender, hookData);

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // initialize pool
        params[0] = abi.encodeWithSelector(_posm.initializePool.selector, pool, startingPrice, hookData);

        // mint liquidity
        params[1] = abi.encodeWithSelector(
            _posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        // add authorized LPs
        address[] memory authorizedLps = new address[](1);
        authorizedLps[0] = address(_posm);
        PredicateHook predicateHook = PredicateHook(_hookAddress);

        vm.startBroadcast();
        predicateHook.addAuthorizedLPs(authorizedLps);
        _tokenApprovals();
        _posm.multicall(params);
        vm.stopBroadcast();
    }

    /**
     * @dev Helper function for encoding mint liquidity operation.
     * @dev Does NOT encode SWEEP, developers should take care when minting liquidity on an ETH pair.
     */
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 liquidity,
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

    /**
     * @dev Approves the token0 and token1 for the posm, swapRouter and permit2
     */
    function _tokenApprovals() internal {
        require(!_currency0.isAddressZero() && !_currency1.isAddressZero(), "Currency must not be zero");

        IERC20 token0 = IERC20(Currency.unwrap(_currency0));
        IERC20 token1 = IERC20(Currency.unwrap(_currency1));

        // approve token0
        token0.approve(address(_permit2), type(uint256).max);
        _permit2.approve(address(token0), address(_posm), type(uint160).max, type(uint48).max);
        token0.approve(address(_swapRouter), type(uint256).max);

        // approve token1
        token1.approve(address(_permit2), type(uint256).max);
        _permit2.approve(address(token1), address(_posm), type(uint160).max, type(uint48).max);
        token1.approve(address(_swapRouter), type(uint256).max);
    }
}
