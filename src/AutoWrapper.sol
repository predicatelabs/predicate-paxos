// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
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
    using CurrencySettler for Currency;
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
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency1), "currency mismatch; currency1 is not wUSDL"
            );
            baseCurrencyIsToken0ForLiquidPool = true;
        } else {
            require(
                address(_wUSDL) == Currency.unwrap(_wUSDLPoolKey.currency0), "currency mismatch; currency0 is not wUSDL"
            );
            baseCurrencyIsToken0ForLiquidPool = false;
        }

        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        baseCurrencyPoolKey = _wUSDLPoolKey;
        router = _router;
        baseCurrencyIsToken0 = baseCurrency < Currency.wrap(wUSDL.asset());
        IERC20(wUSDL.asset()).approve(address(wUSDL), type(uint256).max);
    }

    /**
     * @notice Defines which hook callbacks are active for this contract
     * @return Permissions struct with beforeInitialize, beforeAddLiquidity, and beforeSwap enabled
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            beforeAddLiquidity: true,
            beforeSwap: true,
            beforeSwapReturnDelta: true,
            afterSwap: false,
            afterInitialize: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeDonate: false,
            afterDonate: false,
            afterSwapReturnDelta: false,
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
     * @notice Prevents adding liquidity to the ghost pool
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
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: _getSwapZeroForOneForLiquidPool(params),
            amountSpecified: _getAmountSpecifiedForLiquidPoolSwap(params),
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // Step 2: swap through the liquidity pool
        BalanceDelta delta = _swap(swapParams, hookData);

        // Step 3: transfer the tokens to the hook for settlement
        _transferTokensToHook(params, delta);

        // Step 4: settle the delta for the swap with the pool manager
        _settleDelta(delta);

        // Step 5: transfer the swapped tokens to the user
        _transferTokensToUser(params, delta);

        // Return function selector, empty delta for ghost pool, and zero fee override
        // The actual swap occurs on the liquid pool where fees are charged
        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /**
     * @notice Converts the input/output amount based on wUSDL vault price
     * @dev Depending on swap direction and whether it's exact input or output, converts
     *      between USDL (vault asset) and wUSDL (vault share) using ERC4626.
     * @param params The swap parameters
     * @return The adjusted amount specified
     */
    function _getAmountSpecifiedForLiquidPoolSwap(
        IPoolManager.SwapParams memory params
    ) internal view returns (int256) {
        bool isExactInput = params.amountSpecified < 0;
        if (params.zeroForOne == baseCurrencyIsToken0) {
            return isExactInput ? params.amountSpecified : getUnwrapInputRequired(uint256(params.amountSpecified));
        } else {
            return isExactInput ? -getUnwrapInputRequired(uint256(-params.amountSpecified)) : params.amountSpecified;
        }
    }

    /**
     * @notice Adjusts the zeroForOne flag based on the liquid pool currency configuration
     * @dev This function is used to enable the correct swap direction for the liquidity pool
     * @param params The swap parameters
     * @return The adjusted zeroForOne flag
     */
    function _getSwapZeroForOneForLiquidPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (bool) {
        if (baseCurrencyIsToken0) {
            if (baseCurrencyIsToken0ForLiquidPool) {
                // baseCurrency is token0 for the ghost pool, and baseCurrency is token0 for the predicate pool
                return params.zeroForOne;
            }
            // baseCurrency is token0 for the ghost pool, but wUSDL is token1 for the predicate pool
            return !params.zeroForOne;
        } else {
            if (baseCurrencyIsToken0ForLiquidPool) {
                // wUSDL is token0 for the predicate pool, but baseCurrency is token1 for the liquidity pool
                return !params.zeroForOne;
            }
            // wUSDL is token0 for the ghost pool, and wUSDL is token0 for the predicate pool
            return params.zeroForOne;
        }
    }

    /**
     * @notice Transfers tokens from the user to the hook based on the swap direction.
     * @dev For baseCurrency → USDL swaps, the user sends baseCurrency to this contract.
     *      For USDL → baseCurrency swaps, the user sends USDL, which is wrapped into wUSDL
     *      before the actual swap is executed in the liquid pool.
     * @param params The swap parameters
     * @param delta The balance delta
     */
    function _transferTokensToHook(IPoolManager.SwapParams memory params, BalanceDelta delta) internal {
        bool isExactInput = params.amountSpecified < 0;
        int256 baseCurrencyDelta;
        int256 wUSDLDelta;

        // get the delta for the correct token based on the token0/token1 position of the liquidity pool
        if (baseCurrencyIsToken0ForLiquidPool) {
            baseCurrencyDelta = BalanceDeltaLibrary.amount0(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount1(delta);
        } else {
            baseCurrencyDelta = BalanceDeltaLibrary.amount1(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount0(delta);
        }

        // check if the swap is a baseCurrency -> USDL swap or a USDL -> baseCurrency swap
        // irrespective of the token0/token1 position of the ghost pool
        if (baseCurrencyIsToken0 == params.zeroForOne) {
            // baseCurrency -> USDL swap path
            require(baseCurrencyDelta < 0, "baseCurrency delta is not negative for baseCurrency -> wUSDL swap");
            IERC20(Currency.unwrap(baseCurrency)).transferFrom(
                router.msgSender(), address(this), uint256(-baseCurrencyDelta)
            );
        } else {
            // USDL -> baseCurrency swap path
            require(wUSDLDelta < 0, "wUSDL delta must be negative for USDL -> ERC20 swap");
            uint256 USDLAmount; // amount of USDL to transfer to the hook

            if (isExactInput) {
                // For exact input: User specifies exact USDL amount
                USDLAmount = uint256(-params.amountSpecified);
            } else {
                // For exact output: underlyingAmount is the amount of USDL required to wrap delta1 amount of WUSDL
                USDLAmount = uint256(getWrapInputRequired(uint256(-wUSDLDelta)));
            }

            // transfer the USDL to the auto wrapper
            IERC20(wUSDL.asset()).transferFrom(router.msgSender(), address(this), USDLAmount);

            // Wrap USDL to wUSDL for settlement
            _deposit(USDLAmount);
        }
    }

    /**
     * @notice Transfers tokens to the user
     * @dev This function transfers the tokens to the user based on the swap direction
     * @param params The swap parameters
     * @param delta The balance delta
     */
    function _transferTokensToUser(IPoolManager.SwapParams memory params, BalanceDelta delta) internal {
        int256 baseCurrencyDelta; // delta of the baseCurrency
        int256 wUSDLDelta; // delta of the wUSDL

        // get the delta for the correct token based on the token0/token1 position of the liquidity pool
        if (baseCurrencyIsToken0ForLiquidPool) {
            baseCurrencyDelta = BalanceDeltaLibrary.amount0(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount1(delta);
        } else {
            baseCurrencyDelta = BalanceDeltaLibrary.amount1(delta);
            wUSDLDelta = BalanceDeltaLibrary.amount0(delta);
        }

        // check if the swap is a baseCurrency -> USDL swap or a USDL -> baseCurrency swap
        // irrespective of the token0/token1 position of the ghost pool
        if (baseCurrencyIsToken0 == params.zeroForOne) {
            // baseCurrency -> USDL swap path
            require(wUSDLDelta > 0, "wUSDL delta is not positive for baseCurrency -> wUSDL swap");
            // withdraw the USDL using the wUSDL and transfers to the user
            uint256 redeemAmount = _withdraw(uint256(wUSDLDelta));
            IERC20(wUSDL.asset()).transfer(router.msgSender(), redeemAmount);
        } else {
            // USDL -> baseCurrency swap path
            require(baseCurrencyDelta > 0, "baseCurrency delta is not positive for USDL -> ERC20 swap");
            // transfer the baseCurrency to the user directly
            IERC20(Currency.unwrap(baseCurrency)).transfer(router.msgSender(), uint256(baseCurrencyDelta));
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
     * @notice Settles token balances with the pool manager after a swap on the liquid pool
     * @dev Reconciles token deltas with the pool manager for both sides of the liquidity pool.
     *      If the delta is negative, it settles by transferring tokens in. If positive, it takes the owed amount.
     * @param delta The balance delta from the liquid pool swap that needs to be settled
     */
    function _settleDelta(
        BalanceDelta delta
    ) internal {
        int256 delta0 = BalanceDeltaLibrary.amount0(delta);
        int256 delta1 = BalanceDeltaLibrary.amount1(delta);

        if (delta0 < 0) {
            _settle(baseCurrencyPoolKey.currency0, address(this), uint256(-delta0));
        } else {
            _take(baseCurrencyPoolKey.currency0, address(this), uint256(delta0));
        }

        if (delta1 < 0) {
            _settle(baseCurrencyPoolKey.currency1, address(this), uint256(-delta1));
        } else {
            _take(baseCurrencyPoolKey.currency1, address(this), uint256(delta1));
        }
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
     * @return The amount of USDL required to receive the desired amount of wUSDL
     */
    function getWrapInputRequired(
        uint256 wUSDLAmount
    ) public view returns (int256) {
        return int256(wUSDL.convertToAssets({shares: wUSDLAmount}));
    }

    /**
     * @notice Calculates wUSDL required to obtain a desired amount of USDL
     * @param USDLAmount The target amount of USDL needed
     * @return The amount of wUSDL required to receive the desired amount of USDL
     */
    function getUnwrapInputRequired(
        uint256 USDLAmount
    ) public view returns (int256) {
        return int256(wUSDL.convertToShares({assets: USDLAmount}));
    }
}
