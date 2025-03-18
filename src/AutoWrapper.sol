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
import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";

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
     * @notice The ERC4626 vault contract
     * @dev This is the wrapped token (wUSDL in this case)
     */
    ERC4626 public immutable wUSDL;

    /// @notice The predicate pool key
    /// @dev This is the pool key for the pool with liquidity
    /// @dev example: USDC/wUSDL pool key is {currency0: USDC, currency1: wUSDL, fee: 0}
    PoolKey public predicatePoolKey;

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
     * @notice Indicates whether the wUSDL is token0 in the baseCurrency/wUSDL pool
     */
    bool public immutable wUSDLIsToken0ForPredicatePool;

    /**
     * @notice Indicates whether the base currency is token0 in the baseCurrency/USDL pool
     */
    bool public immutable baseCurrencyIsToken0;

    /**
     * @notice Creates a new ERC4626 wrapper hook
     * @param _manager The Uniswap V4 pool manager
     * @param _wUSDL The ERC4626 vault contract address
     * @param _baseCurrency The base currency for wUSDL pool(e.g. USDC)
     * @param _predicatePoolKey The pool key for the pool with liquidity
     * @param _router The V4 router
     */
    constructor(
        IPoolManager _manager,
        ERC4626 _wUSDL, // _wUSDL.asset() is USDL
        Currency _baseCurrency, // _baseCurrency is the other asset of the wUSDL pool. ex USDC
        PoolKey memory _predicatePoolKey,
        ISimpleV4Router _router
    ) BaseHook(_manager) {
        if (_baseCurrency == _predicatePoolKey.currency0) {
            // baseCurrency/wUSDL pool
            require(
                address(_wUSDL) == Currency.unwrap(_predicatePoolKey.currency1),
                "currency mismatch; currency1 is not wUSDL"
            );
            wUSDLIsToken0ForPredicatePool = false;
        } else {
            require(
                address(_wUSDL) == Currency.unwrap(_predicatePoolKey.currency0),
                "currency mismatch; currency0 is not wUSDL"
            );
            wUSDLIsToken0ForPredicatePool = true;
        }

        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        predicatePoolKey = _predicatePoolKey;
        router = _router;
        baseCurrencyIsToken0 = baseCurrency < Currency.wrap(wUSDL.asset());
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
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        require(sender == address(router), "sender is not the router");

        // Determines the amounts and direction of the swap through the liquidity pool
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: _getSwapZeroForOneForLiquidityPool(params),
            amountSpecified: _getAmountSpecifiedForLiquidityPool(params),
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        // swap through the liquidity pool
        BalanceDelta delta = _swap(swapParams, hookData);

        // transfer the tokens to the hook
        _transferToHook(params, delta);

        // settle the delta
        _settleDelta(delta);

        // transfer the swappedtokens to the user
        _transferToUser(params, delta);

        // Return function selector, empty delta for ghost pool, and zero fee override
        // The actual swap occurs on the liquid pool where fees are charged
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
            return isExactInput ? params.amountSpecified : getUnwrapInputRequired(uint256(params.amountSpecified));
        } else {
            return isExactInput ? -getUnwrapInputRequired(uint256(-params.amountSpecified)) : params.amountSpecified;
        }
    }

    /**
     * @notice Adjusts the zeroForOne flag for the underlying liquidity pool swap based on the swap direction
     * @param params The swap parameters
     * @return The adjusted zeroForOne flag
     */
    function _getSwapZeroForOneForLiquidityPool(
        IPoolManager.SwapParams memory params
    ) internal view returns (bool) {
        // todo: implement this
        return params.zeroForOne;
    }

    /**
     * @notice Transfers tokens to the hook based on swap parameters
     * @param params The swap parameters
     * @param delta The balance delta
     * @dev This function transfers the tokens to the hook based on the swap parameters and the balance delta
     */
    function _transferToHook(IPoolManager.SwapParams memory params, BalanceDelta delta) internal {
        bool isExactInput = params.amountSpecified < 0;
        int256 delta0 = BalanceDeltaLibrary.amount0(delta);
        int256 delta1 = BalanceDeltaLibrary.amount1(delta);

        if (baseCurrencyIsToken0 == params.zeroForOne) {
            // baseCurrency -> USDL swap path
            require(delta0 < 0, "baseCurrency delta is not negative for baseCurrency -> wUSDL swap");
            IERC20(Currency.unwrap(baseCurrency)).transferFrom(router.msgSender(), address(this), uint256(-delta0));
        } else {
            // USDL -> baseCurrency swap path
            require(delta1 < 0, "wUSDL delta must be negative for USDL -> ERC20 swap");
            uint256 USDLAmount;
            if (isExactInput) {
                // For exact input: User specifies exact USDL amount
                USDLAmount = uint256(-params.amountSpecified);
            } else {
                // For exact output: underlyingAmount is the amount of USDL required to wrap delta1 amount of WUSDL
                USDLAmount = uint256(getWrapInputRequired(uint256(-delta1)));
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
    function _transferToUser(IPoolManager.SwapParams memory params, BalanceDelta delta) internal {
        int256 delta0 = BalanceDeltaLibrary.amount0(delta);
        int256 delta1 = BalanceDeltaLibrary.amount1(delta);

        if (baseCurrencyIsToken0 == params.zeroForOne) {
            // baseCurrency -> USDL swap path
            require(delta1 > 0, "wUSDL delta is not positive for baseCurrency -> wUSDL swap");
            // withdraw the USDL from the wUSDL and transfers to the user
            uint256 redeemAmount = _withdraw(uint256(delta1));
            IERC20(wUSDL.asset()).transfer(router.msgSender(), redeemAmount);
        } else {
            // transfer the baseCurrency to the user directly
            uint256 baseCurrencyBalance = IERC20(Currency.unwrap(baseCurrency)).balanceOf(address(this));
            IERC20(Currency.unwrap(baseCurrency)).transfer(router.msgSender(), baseCurrencyBalance);
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
        (,, int256 deltaBefore0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
        (,, int256 deltaBefore1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));
        require(deltaBefore0 == 0, "deltaBefore0 is not 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not 0");

        delta = poolManager.swap(predicatePoolKey, params, hookData);

        return delta;
    }

    /**
     * @notice Settles token balances with the pool manager after a swap on the liquid pool
     * @dev Handles both tokens in the pair, settling debts or taking excess tokens as needed
     * @param delta The balance delta from the liquid pool swap that needs to be settled
     */
    function _settleDelta(
        BalanceDelta delta
    ) internal {
        int256 delta0 = BalanceDeltaLibrary.amount0(delta);
        int256 delta1 = BalanceDeltaLibrary.amount1(delta);

        if (delta0 < 0) {
            _settle(predicatePoolKey.currency0, address(this), uint256(-delta0));
        } else {
            _take(predicatePoolKey.currency0, address(this), uint256(delta0));
        }

        if (delta1 < 0) {
            _settle(predicatePoolKey.currency1, address(this), uint256(-delta1));
        } else {
            _take(predicatePoolKey.currency1, address(this), uint256(delta1));
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

    /**
     * @notice Retrieves balances and delta for a specific token
     * @param currency The token to query (exchangeToken or wUSDL)
     * @param user The user address
     * @param deltaHolder The address responsible for settling deltas (typically this contract)
     * @return userBalance The user's current balance
     * @return poolBalance The pool manager's current balance
     * @return delta The outstanding delta owed to/from the pool manager
     */
    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    ) internal view returns (uint256 userBalance, uint256 poolBalance, int256 delta) {
        userBalance = CurrencyLibrary.balanceOf(currency, user);
        poolBalance = CurrencyLibrary.balanceOf(currency, address(poolManager));
        delta = poolManager.currencyDelta(deltaHolder, currency);
    }
}
