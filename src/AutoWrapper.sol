// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {toBalanceDelta, BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import {console} from "forge-std/console.sol";

/**
 * @title USDL Ghost Pool Swap & Wrap Hook
 * @author Predicate Labs
 * @notice Uniswap V4 hook for routing swaps between a ghost pool and a liquid ERC20/wUSDL pool, while automatically wrapping/unwrapping USDL ↔ wUSDL
 * @dev This hook is designed to be used with a ghost pool. It intercepts swaps and performs wrapping logic with an ERC4626 vault and executes swaps against the pre-configured liquid ERC20/wUSDL pool.
 */
contract AutoWrapper is BaseHook, DeltaResolver {
    using SafeCast for uint256;
    using SafeCast for int256;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    /**
     * @notice Thrown when attempting to add liquidity on the ghost pool
     * @dev All liquidity operations must be performed directly on the liquid ERC20/wUSDL pool,
     *      as the ghost pool is only an interface for users and doesn't hold actual liquidity
     */
    error LiquidityNotAllowed();

    /**
     * @notice Thrown when initializing a pool with non-zero fee
     * @dev Ghost pools must use zero fee as fees
     */
    error InvalidPoolFee();

    /**
     * @notice Thrown when the caller is not the router
     * @dev This is a security measure to ensure that only the router can call the pool manager
     */
    error CallerIsNotRouter();

    /**
     * @notice The ERC4626 vault contract
     * @dev This is the wrapped token (wUSDL in this case)
     */
    ERC4626 public immutable wUSDL;

    /// @notice The predicate pool key
    /// @dev This is the pool key for the pool with liquidity
    /// @dev example: USDC/wUSDL pool key is {currency0: USDC, currency1: wUSDL, fee: 0}
    PoolKey public wUSDLPoolKey;

    /**
     * @notice Reference to the router handling user swap requests
     * @dev Used to access the actual message sender. This is a trusted contract.
     */
    ISimpleV4Router public router;

    /**
     * @notice The base currency for this USDL pool (e.g. USDC)
     */
    Currency public immutable baseCurrency;

    /**
     * @notice Indicates whether the base currency is token0 in the baseCurrency/wUSDL pool
     */
    bool public immutable baseCurrencyIsToken0ForPredicatePool;

    /**
     * @notice Indicates whether the base currency is token0 in the baseCurrency/USDL pool
     */
    bool public immutable baseCurrencyIsToken0;

    /**
     * @notice Creates a new ERC4626 wrapper hook
     * @param _manager The Uniswap V4 pool manager
     * @param _wUSDL The ERC4626 vault contract address
     * @param _baseCurrency The base currency for wUSDL pool(e.g. USDC)
     * @param _wUSDLPoolKey The pool key for the pool with liquidity
     * @param _router The V4 router
     */
    constructor(
        IPoolManager _manager,
        ERC4626 _wUSDL, // _wUSDL.asset() is USDL
        Currency _baseCurrency, // _baseCurrency is the other asset of the wUSDL pool. ex USDC
        PoolKey memory _wUSDLPoolKey,
        ISimpleV4Router _router
    ) BaseHook(_manager) {
        if (_baseCurrency == _wUSDLPoolKey.currency0) {
            // baseCurrency/wUSDL pool
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency1), "currency mismatch; currency1 is not wUSDL"
            );
            baseCurrencyIsToken0ForPredicatePool = true;
        } else {
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency0), "currency mismatch; currency0 is not wUSDL"
            );
            baseCurrencyIsToken0ForPredicatePool = false; // false for mainnet
        }

        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        wUSDLPoolKey = _wUSDLPoolKey; // predicate pool key
        router = _router;
        baseCurrencyIsToken0 = baseCurrency < Currency.wrap(wUSDL.asset()); // true for mainnet
        IERC20(wUSDL.asset()).approve(address(wUSDL), type(uint256).max);
    }

    /**
     * @notice Defines hook permissions for the Uniswap V4 pool manager
     * @dev Enables only the callbacks needed for ghost pool operations
     * @return Hooks.Permissions struct with required callback permissions enabled
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            beforeAddLiquidity: true,
            beforeSwap: true,
            beforeSwapReturnDelta: true,
            afterSwap: true,
            afterSwapReturnDelta: false,
            afterInitialize: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeDonate: false,
            afterDonate: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Validates pool initialization parameters for the ghost pool
     * @dev Ensures ghost pool has zero fee since actual fees will be charged on the liquid pool
     * @param poolKey The pool configuration being initialized
     * @return The function selector if validation passes
     */
    function _beforeInitialize(address, PoolKey calldata poolKey, uint160) internal view override returns (bytes4) {
        if (poolKey.fee != 0) revert InvalidPoolFee();
        return IHooks.beforeInitialize.selector;
    }

    /**
     * @notice Validates the balance delta for the ghost pool
     * @dev This ensures no swap occurred on the ghost pool
     * @param delta The balance delta
     * @return The function selector and delta
     */
    function _afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) internal view override returns (bytes4, int128) {
        // this ensures no swap occurred on the ghost pool
        require(
            BalanceDeltaLibrary.amount0(delta) == 0 && BalanceDeltaLibrary.amount1(delta) == 0,
            "Balance Delta for ghost pool is not zero"
        );
        return (IHooks.afterSwap.selector, 0);
    }

    /**
     * @notice Prevents direct liquidity operations on the ghost pool
     * @dev Unconditionally reverts as liquidity must be added to the liquid ERC20/wUSDL pool
     * @return bytes4 Never returns as the function always reverts
     */
    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert LiquidityNotAllowed();
    }

    /**
     * @notice Intercepts swaps on the ghost pool and routes them through the liquid pool
     * @dev Core function implementing the routing logic between pools. For ERC20→USDL swaps,
     *      it routes through the liquid pool (ERC20→wUSDL), then unwraps to USDL.
     *      For USDL→ERC20 swaps, it wraps USDL to wUSDL, executes the swap on the liquid
     *      pool, and returns ERC20 to the user. Preserves exact input/output semantics throughout.
     * @param params The swap parameters on the ghost pool
     * @param hookData Encoded data containing authorization information for the liquid pool swap
     * @return selector The function selector indicating success
     * @return swapDelta Empty delta for the ghost pool (actual deltas are handled on the liquid pool)
     * @return lpFeeOverride Always 0 as fees are handled by the liquid pool
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        if (sender != address(router)) revert CallerIsNotRouter();

        bool isExactInput = params.amountSpecified < 0;

        // Step 1: Determines the amounts and direction of the swap for the underlying liquidity pool
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: _getSwapZeroForOneForLiquidityPool(params),
            amountSpecified: _getAmountSpecifiedForLiquidityPool(params),
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Step 2: swap through the liquidity pool
        BalanceDelta delta = _swap(swapParams, hookData);
        int256 baseCurrencyDelta; // delta of the baseCurrency
        int256 wUSDLDelta; // delta of the wUSDL

        if (baseCurrencyIsToken0ForPredicatePool) {
            baseCurrencyDelta = BalanceDeltaLibrary.amount0(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount1(delta);
        } else {
            baseCurrencyDelta = BalanceDeltaLibrary.amount1(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount0(delta);
        }

        // Step 3: settle the delta for the swap with the pool manager and calculate the swap delta
        if (params.zeroForOne == baseCurrencyIsToken0) {
            // baseCurrency -> USDL swap path
            _take(Currency.wrap(address(wUSDL)), address(this), uint256(wUSDLDelta)); // from the underlying swap, we take wUSDL and only owe USDC

            uint256 usdlDelta = _withdraw(uint256(wUSDLDelta));

            _settle(Currency.wrap(wUSDL.asset()), address(this), uint256(usdlDelta));

            int128 amountUnspecified = isExactInput ? -usdlDelta.toInt256().toInt128() : -baseCurrencyDelta.toInt128();

            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        } else {
            // USDL -> baseCurrency swap path
            // take the USDL from the user
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : uint256(getWrapInputRequired(uint256(-wUSDLDelta)));
            IERC20(wUSDL.asset()).transferFrom(router.msgSender(), address(this), inputAmount);

            uint256 wUSDLAmount = _deposit(inputAmount);
            require(wUSDLAmount == uint256(-wUSDLDelta), "wUSDLAmount mismatch");

            _settle(Currency.wrap(address(wUSDL)), address(this), wUSDLAmount);
            _take(baseCurrency, address(this), uint256(baseCurrencyDelta));

            IERC20(Currency.unwrap(baseCurrency)).transfer(router.msgSender(), uint256(baseCurrencyDelta));

            int128 amountUnspecified = isExactInput ? int128(0) : -baseCurrencyDelta.toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), 0);
        }

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /**
     * @notice Adjusts the amount specified for the underlying liquidity pool swap based on the swap direction
     * @param params The swap parameters
     * @return The adjusted amount specified
     */
    function _getAmountSpecifiedForLiquidityPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (int256) {
        // todo: verify this works for all cases
        bool isExactInput = params.amountSpecified < 0;
        if (params.zeroForOne == baseCurrencyIsToken0) {
            // USDC -> USDL pool
            return isExactInput ? params.amountSpecified : getUnwrapInputRequired(uint256(params.amountSpecified));
        } else {
            // USDL -> USDC ex. 5 USDL as output
            // WUSDL/USDC pool
            return isExactInput ? -getUnwrapInputRequired(uint256(-params.amountSpecified)) : params.amountSpecified;
        }
    }

    /**
     * @notice Adjusts the zeroForOne flag for the underlying liquidity pool swap based on the swap direction
     * @dev This function is used to enable the correct swap direction for the liquidity pool
     * @param params The swap parameters
     * @return The adjusted zeroForOne flag
     */
    function _getSwapZeroForOneForLiquidityPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (bool) {
        if (baseCurrencyIsToken0) {
            if (baseCurrencyIsToken0ForPredicatePool) {
                // baseCurrency is token0 for the ghost pool, and baseCurrency is token0 for the predicate pool
                return params.zeroForOne;
            }
            // baseCurrency is token0 for the ghost pool, but wUSDL is token1 for the predicate pool
            return !params.zeroForOne;
        } else {
            if (baseCurrencyIsToken0ForPredicatePool) {
                // wUSDL is token0 for the predicate pool, but baseCurrency is token1 for the liquidity pool
                return !params.zeroForOne;
            }
            // wUSDL is token0 for the ghost pool, and wUSDL is token0 for the predicate pool
            return params.zeroForOne;
        }
    }

    /**
     * @notice Executes a swap on the liquid ERC20/wUSDL pool
     * @dev Routes the swap parameters through the predicate pool, passing along authorization data
     * @param params The swap parameters for the liquid pool
     * @param hookData Authorization data needed for the predicate pool
     * @return delta The balance delta resulting from the swap on the liquid pool
     */
    function _swap(
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) internal returns (BalanceDelta delta) {
        return poolManager.swap(wUSDLPoolKey, params, hookData);
    }

    /**
     * @notice Implementation of DeltaResolver's payment method
     * @dev Transfers tokens to the pool manager to settle negative deltas
     * @param token The token to transfer
     * @param amount The amount to transfer
     */
    function _pay(Currency token, address, uint256 amount) internal override {
        token.transfer(address(poolManager), amount);
    }

    /**
     * @notice Deposits USDL to receive wUSDL via the ERC4626 vault
     * @dev Used during USDL → ERC20 swaps to get wUSDL for the liquid pool swap
     * @param USDLAmount The amount of USDL to deposit
     * @return wUSDLAmount The amount of wUSDL received
     */
    function _deposit(
        uint256 USDLAmount
    ) internal returns (uint256) {
        return wUSDL.deposit({assets: USDLAmount, receiver: address(this)});
    }
    /**
     * @notice Withdraws wUSDL to receive USDL via the ERC4626 vault
     * @dev Used during ERC20 → USDL swaps to convert wUSDL from the liquid pool to USDL for the user
     * @param wUSDLAmount The amount of wUSDL to redeem
     * @return USDLAmount The amount of USDL received
     */

    function _withdraw(
        uint256 wUSDLAmount
    ) internal returns (uint256) {
        return wUSDL.redeem({shares: wUSDLAmount, receiver: address(this), owner: address(this)});
    }

    /**
     * @notice Calculates USDL required to obtain a desired amount of wUSDL
     * @param wUSDLAmount The target amount of wUSDL needed
     * @return wUSDL amount of USDL required
     */
    function getWrapInputRequired(
        uint256 wUSDLAmount
    ) public view returns (int256) {
        return int256(wUSDL.convertToAssets({shares: wUSDLAmount}));
    }

    /**
     * @notice Calculates wUSDL required to obtain a desired amount of USDL
     * @param USDLAmount The target amount of USDL needed
     * @return The amount of wUSDL required
     */
    function getUnwrapInputRequired(
        uint256 USDLAmount
    ) public view returns (int256) {
        return int256(wUSDL.convertToShares({assets: USDLAmount}));
    }
}
