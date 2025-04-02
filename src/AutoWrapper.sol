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
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title AutoWrapper Swap Hook for USDL
 * @author Predicate Labs
 * @notice A V4 hook for swapping USDL, a rebasing asset, against some base currency (e.g. USDC)
 * @dev This hook is intended to be used with a "ghost pool"-a non-liquid pool that acts as an interface
 *      for swapping USDL against wUSDL/baseCurrency pool.
 */
contract AutoWrapper is BaseHook, DeltaResolver {
    using SafeCast for uint256;
    using SafeCast for int256;
    using CurrencyLibrary for Currency;
    using TransientStateLibrary for IPoolManager;

    /**
     * @notice Thrown when attempting to add liquidity on the ghost pool
     * @dev All liquidity operations must be performed directly on the liquid ERC20/wUSDL pool,
     *      as the ghost pool is only an interface for swapping USDL and does not hold actual liquidity
     */
    error LiquidityNotAllowed();

    /**
     * @notice Thrown when initializing a pool with non-zero fee
     * @dev Ghost pools must use zero fee as fees
     */
    error InvalidPoolFee();

    /**
     * @notice Thrown when the caller is not the router
     * @dev This is a security measure to ensure that only the configured router can call the pool manager
     */
    error CallerIsNotRouter();

    /**
     * @notice The ERC4626 vault contract
     * @dev This is the wrapped token (wUSDL in this case)
     */
    ERC4626 public immutable wUSDL;

    /**
     * @notice The wUSDL/baseCurrency pool key
     * @dev This is the pool key for the liquid pool
     */
    PoolKey public baseCurrencyPoolKey;

    /**
     * @notice Reference to the router handling user swap requests
     * @dev Used to access the actual message sender. This is a trusted contract.
     */
    V4Router public router;

    /**
     * @notice The base currency for this ghost pool and the liquid pool
     */
    Currency public immutable baseCurrency;

    /**
     * @notice Indicates whether the base currency is token0 in the baseCurrency/wUSDL pool
     */
    bool public immutable baseCurrencyIsToken0ForLiquidPool;

    /**
     * @notice Indicates whether the base currency is token0 in this ghost pool
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
        ERC4626 _wUSDL,
        Currency _baseCurrency,
        PoolKey memory _wUSDLPoolKey,
        V4Router _router
    ) BaseHook(_manager) {
        if (_baseCurrency == _wUSDLPoolKey.currency0) {
            // baseCurrency/wUSDL pool
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency1), "currency mismatch; currency1 is not wUSDL"
            );
            baseCurrencyIsToken0ForLiquidPool = true;
        } else {
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency0), "currency mismatch; currency0 is not wUSDL"
            );
            baseCurrencyIsToken0ForLiquidPool = false; // false for mainnet
        }

        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        baseCurrencyPoolKey = _wUSDLPoolKey; // predicate pool key
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
     * @notice Handles swaps for or with USDL on the ghost pool
     * @dev Core function implementing the wrapping and routing of the swap against the liquid pool.
     *      For ERC20→USDL swaps, it routes through the liquid pool (ERC20→wUSDL), then unwraps to USDL.
     *      For USDL→ERC20 swaps, it wraps USDL to wUSDL, executes the swap on the liquid
     *      pool, and returns ERC20 directly to the user.
     * @param params The swap parameters on the ghost pool
     * @param hookData Encoded data containing authorization information for the liquid pool swap
     * @return selector The function selector indicating success
     * @return swapDelta Empty delta for the ghost pool (actual deltas are handled on the liquid pool)
     * @return lpFeeOverride Always 0 as fees are handled by the liquid pool
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        if (sender != address(router)) revert CallerIsNotRouter();

        // Step 1: Determines the amounts and direction of the swap for the underlying liquidity pool
        bool swapZeroForOne = _getSwapZeroForOneForLiquidPool(params);
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: swapZeroForOne,
            amountSpecified: _getAmountSpecifiedForLiquidPool(params),
            sqrtPriceLimitX96: _getSqrtPriceLimitX96ForLiquidPool(swapZeroForOne)
        });

        // Step 2: swap through the liquidity pool
        BalanceDelta delta = _swap(swapParams, hookData);
        int256 baseCurrencyDelta; // delta of the baseCurrency
        int256 wUSDLDelta; // delta of the wUSDL

        if (baseCurrencyIsToken0ForLiquidPool) {
            baseCurrencyDelta = BalanceDeltaLibrary.amount0(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount1(delta);
        } else {
            baseCurrencyDelta = BalanceDeltaLibrary.amount1(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount0(delta);
        }

        // Step 3: settle the delta for the swap with the pool manager and calculate the swap delta
        bool isExactInput = params.amountSpecified < 0;
        if (params.zeroForOne == baseCurrencyIsToken0) {
            // baseCurrency -> USDL swap path
            _take(Currency.wrap(address(wUSDL)), address(this), uint256(wUSDLDelta));
            uint256 usdlDelta = _withdraw(uint256(wUSDLDelta));
            _settle(Currency.wrap(wUSDL.asset()), address(this), uint256(usdlDelta));
            int128 amountUnspecified = isExactInput ? -usdlDelta.toInt256().toInt128() : -baseCurrencyDelta.toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        } else {
            // USDL -> baseCurrency swap path
            // Note: UniversalRouter sends USDL to the poolManager at start of swap
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : uint256(getWrapInputRequired(uint256(-wUSDLDelta)));
            _take(Currency.wrap(wUSDL.asset()), address(this), inputAmount);
            uint256 wUSDLAmount = _deposit(inputAmount);
            _settle(Currency.wrap(address(wUSDL)), address(this), wUSDLAmount);
            int128 amountUnspecified = isExactInput ? -baseCurrencyDelta.toInt128() : inputAmount.toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        }

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /**
     * @notice Converts the input/output amount based on wUSDL vault price
     * @dev Depending on swap direction and whether it's exact input or output, converts
     *      between USDL (vault asset) and wUSDL (vault share) using ERC4626.
     * @param params The swap parameters
     * @return amount The adjusted amount specified
     */
    function _getAmountSpecifiedForLiquidPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (int256) {
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
     * @notice Adjusts the sqrtPriceLimitX96 for the underlying liquidity pool swap based on the swap direction
     * @dev This function is used to enable the correct swap direction for the liquidity pool
     * @return sqrtPriceLimitX96 The adjusted sqrtPriceLimitX96 set to max or min sqrtPrice
     */
    function _getSqrtPriceLimitX96ForLiquidPool(
        bool swapZeroForOne
    ) internal pure returns (uint160) {
        return swapZeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    /**
     * @notice Adjusts the zeroForOne flag for the underlying liquidity pool swap based on the swap direction
     * @dev This function is used to enable the correct swap direction for the liquidity pool
     * @param params The swap parameters
     * @return flag The adjusted zeroForOne flag
     */
    function _getSwapZeroForOneForLiquidPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (bool) {
        if (baseCurrencyIsToken0) {
            if (baseCurrencyIsToken0ForLiquidPool) {
                // baseCurrency is token0 for the ghost pool, and baseCurrency is token0 for the predicate pool
                return params.zeroForOne;
            }
            // baseCurrency is token0 for the ghost pool and baseCurrency is token1 for the predicate pool
            return !params.zeroForOne;
        } else {
            if (baseCurrencyIsToken0ForLiquidPool) {
                // baseCurrency is token1 for the ghost pool and baseCurrency is token0 for the predicate pool
                return !params.zeroForOne;
            }
            // baseCurrency is token1 for the ghost pool and baseCurrency is token1 for the predicate pool
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
        return poolManager.swap(baseCurrencyPoolKey, params, hookData);
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
     * @param usdlAmount The amount of USDL to deposit
     * @return wUSDLAmount The amount of wUSDL received
     */
    function _deposit(
        uint256 usdlAmount
    ) internal returns (uint256) {
        return wUSDL.deposit({assets: usdlAmount, receiver: address(this)});
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
     * @param usdlAmount The target amount of USDL needed
     * @return The amount of wUSDL required
     */
    function getUnwrapInputRequired(
        uint256 usdlAmount
    ) public view returns (int256) {
        return int256(wUSDL.convertToShares({assets: usdlAmount}));
    }
}
