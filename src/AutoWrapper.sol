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
 * @title USDL Auto Wrapper Hook
 * @author Predicate Labs
 * @notice Uniswap V4 hook implementing an automatic wrapper/unwrapper for USDL and wUSDL
 * @dev This contract extends BaseTokenWrapperHook to provide a conversion between the yield bearing
 *      Lift Dollar (USDL) and its wrapped version (wUSDL) through a V4 Ghost pool.
 * @dev This contract also implements DeltaResolver to handle the token delta settlement
 */
contract AutoWrapper is BaseHook, DeltaResolver {
    using SafeCast for uint256;
    using SafeCast for int256;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    /// @notice Thrown when attempting to add or remove liquidity
    /// @dev Liquidity operations are blocked since all liquidity is managed by the token wrapper
    error LiquidityNotAllowed();

    /// @notice Thrown when initializing a pool with non-zero fee
    /// @dev Fee must be 0 as wrapper pools don't charge fees
    error InvalidPoolFee();

    /// @notice The ERC4626 vault contract
    /// @dev This is the wrapped token (wUSDL in this case)
    ERC4626 public immutable wUSDL;

    /// @notice The predicate pool key
    /// @dev This is the pool key for the pool with liquidity
    /// @dev example: USDC/wUSDL pool key is {currency0: USDC, currency1: wUSDL, fee: 0}
    PoolKey public predicatePoolKey;

    /// @notice The V4 router
    ISimpleV4Router public router;

    /// @notice The base currency for wUSDL pool(e.g. USDC)
    Currency public immutable baseCurrency;

    /// @notice Indicates whether the wUSDL is token0 in the baseCurrency/wUSDL pool
    bool public immutable wUSDLIsToken0;

    /// @notice Indicates whether the base currency is token0 in the baseCurrency/USDL pool
    bool public immutable baseCurrencyIsToken0;

    /// @notice Creates a new ERC4626 wrapper hook
    /// @param _manager The Uniswap V4 pool manager
    /// @param _wUSDL The ERC4626 vault contract address
    /// @param _baseCurrency The base currency for wUSDL pool(e.g. USDC)
    /// @param _predicatePoolKey The pool key for the pool with liquidity
    /// @param _router The V4 router
    constructor(
        IPoolManager _manager,
        ERC4626 _wUSDL, // _wUSDL.asset() is USDL
        IERC20 _baseCurrency, // _baseCurrency is the other asset of the wUSDL pool. ex USDC
        PoolKey calldata _predicatePoolKey,
        ISimpleV4Router _router
    ) BaseHook(_manager) {
        if (address(_baseCurrency) == Currency.unwrap(_predicatePoolKey.currency0)) {
            // baseCurrency/wUSDL pool
            require(
                address(_wUSDL) == Currency.unwrap(_predicatePoolKey.currency1),
                "currency mismatch; currency1 is not wUSDL"
            );
            wUSDLIsToken0 = false;
        } else {
            require(
                address(_wUSDL) == Currency.unwrap(_predicatePoolKey.currency0),
                "currency mismatch; currency0 is not wUSDL"
            );
            wUSDLIsToken0 = true;
        }

        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        predicatePoolKey = _predicatePoolKey;
        router = _router;
        baseCurrencyIsToken0 = baseCurrency < address(wUSDL.asset());
        IERC20(Currency.unwrap(baseCurrency)).approve(address(wUSDL), type(uint256).max);
    }

    /// @inheritdoc BaseHook
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

    /// @notice Validates pool initialization parameters
    /// @dev Ensures pool contains  zero fee
    /// @param poolKey The pool configuration including tokens and fee
    /// @return The function selector if validation passes
    function _beforeInitialize(address, PoolKey calldata poolKey, uint160) internal view override returns (bytes4) {
        if (poolKey.fee != 0) revert InvalidPoolFee();
        return IHooks.beforeInitialize.selector;
    }

    /// @notice Prevents liquidity operations on wrapper pools
    /// @dev Always reverts as liquidity is managed through the token wrapper
    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert LiquidityNotAllowed();
    }

    /// @notice Handles token wrapping and unwrapping during swaps
    /// @dev Processes both exact input (amountSpecified < 0) and exact output (amountSpecified > 0) swaps
    /// @param params The swap parameters including direction and amount
    /// @return selector The function selector
    /// @return swapDelta The input/output token amounts for pool accounting
    /// @return lpFeeOverride The fee override (always 0 for wrapper pools)
    function _beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        bool isExactInput = params.amountSpecified < 0;
        IPoolManager.SwapParams memory swapParams = params;
        BalanceDelta delta;

        // 4 possible cases:
        // pool is USDL/baseCurrency and underlying is baseCurrency/wUSDL
        // pool is USDL/baseCurrency and underlying is wUSDL/baseCurrency
        // pool is baseCurrency/USDL and underlying is baseCurrency/wUSDL
        // pool is baseCurrency/USDL and underlying is wUSDL/baseCurrency
        // we need to check which case we are in and then swap through the correct underlying liquidity pool

        // case 1: USDL/baseCurrency and baseCurrency/wUSDL

        if (baseCurrencyIsToken0 == params.zeroForOne) {
            // ex USDC -> wUSDL
            // calculate the amount of baseCurrency to swap through underlying liquidity pool
            swapParams.amountSpecified =
                isExactInput ? params.amountSpecified : getUnwrapInputRequired(uint256(params.amountSpecified));
            delta = _swap(swapParams, hookData);

            // calculate the amount of baseCurrency to settle the delta
            // delta0 is the amount of baseCurrency required to settle the delta
            int256 delta0 = BalanceDeltaLibrary.amount0(delta);
            require(delta0 < 0, "baseCurrency delta is not negative for baseCurrency -> wUSDL swap");
            IERC20(Currency.unwrap(baseCurrency)).transferFrom(router.msgSender(), address(this), uint256(-delta0));

            // settle the delta
            // takes baseCurrency from the auto wrapper and settles the delta with the pool manager
            _settleDelta(delta);

            // withdraw the USDL from the vault and transfers to the user
            uint256 redeemAmount = _withdraw(IERC20(Currency.unwrap(wrapperCurrency)).balanceOf(address(this)));
            IERC20(Currency.unwrap(underlyingCurrency)).transfer(router.msgSender(), redeemAmount);
        } else {
            // USDL -> USDC
            // calculate the amount of WUSDL to swap through underlying liquidity pool
            swapParams.amountSpecified =
                isExactInput ? -getUnwrapInputRequired(uint256(-params.amountSpecified)) : params.amountSpecified;
            delta = _swap(swapParams, hookData);
            uint256 underlyingAmount;

            // calculate the amount of USDL to deposit and transfer to the auto wrapper
            if (isExactInput) {
                underlyingAmount = uint256(-params.amountSpecified);

                // transfer the USDL to the auto wrapper
                IERC20(Currency.unwrap(underlyingCurrency)).transferFrom(
                    router.msgSender(), address(this), underlyingAmount
                );
            } else {
                // delta1 is the amount of WUSDL required to settle the delta
                // ex -6 WUSDL is required to settle the delta
                int256 delta1 = BalanceDeltaLibrary.amount1(delta);
                require(delta1 < 0, "wUSDL delta is not negative for USDL -> USDC swap");

                // underlyingAmount is the amount of USDL required to wrap delta1 amount of WUSDL
                underlyingAmount = uint256(getWrapInputRequired(uint256(-delta1)));
                IERC20(Currency.unwrap(underlyingCurrency)).transferFrom(
                    router.msgSender(), address(this), underlyingAmount
                );
            }
            // deposit the USDL
            uint256 wrappedAmount = _deposit(underlyingAmount);

            // settle the delta
            _settleDelta(delta); // takes WUSDL from the auto wrapper and settles the delta with the pool manager

            // transfer the USDC to the user directly
            uint256 usdcBalance = usdc.balanceOf(address(this));
            usdc.transfer(router.msgSender(), usdcBalance);
        }
        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /// @notice Swaps through the underlying liquidity pool
    /// @dev This function is used to swap through the underlying liquidity pool and settle the token delta as well
    /// @param params The swap parameters
    /// @param hookData The hook data
    function _swap(
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) internal returns (BalanceDelta delta) {
        (,, int256 deltaBefore0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
        (,, int256 deltaBefore1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));
        require(deltaBefore0 == 0, "deltaBefore0 is not 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not 0");

        delta = poolManager.swap(predicatePoolKey, params, hookData); // USDC/WUSDL pool

        return delta;
    }

    /// @notice Settles the delta for the underlying currency
    /// @param delta The delta to settle
    /// @dev This function is used to settle the delta for the underlying currency
    /// @dev This function is called when the delta is not 0
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

    /// @inheritdoc DeltaResolver
    function _pay(Currency token, address, uint256 amount) internal override {
        token.transfer(address(poolManager), amount);
    }

    /// @notice Deposits underlying tokens to receive wrapper tokens
    /// @param underlyingAmount The amount of underlying tokens to deposit
    /// @return wrappedAmount The amount of wrapper tokens received
    function _deposit(
        uint256 underlyingAmount
    ) internal returns (uint256) {
        return vault.deposit({assets: underlyingAmount, receiver: address(this)});
    }

    /// @notice Withdraws wrapper tokens to receive underlying tokens
    /// @param wrappedAmount The amount of wrapper tokens to withdraw
    /// @return underlyingAmount The amount of underlying tokens received
    function _withdraw(
        uint256 wrappedAmount
    ) internal returns (uint256) {
        return vault.redeem({shares: wrappedAmount, receiver: address(this), owner: address(this)});
    }

    /// @notice Calculates underlying tokens needed to receive desired wrapper tokens
    /// @param wrappedAmount The desired amount of wrapper tokens
    function getWrapInputRequired(
        uint256 wrappedAmount
    ) public view returns (int256) {
        return int256(vault.convertToAssets({shares: wrappedAmount}));
    }

    /// @notice Calculates wrapper tokens needed to receive desired underlying tokens
    /// @param underlyingAmount The desired amount of underlying tokens
    function getUnwrapInputRequired(
        uint256 underlyingAmount
    ) public view returns (int256) {
        return int256(vault.convertToShares({assets: underlyingAmount}));
    }

    /// @notice Fetches the user balance, pool balance, and delta for a given currency
    /// @param currency The currency to fetch the balances and delta for
    /// @param user The address of the user to fetch the balances for
    /// @param deltaHolder The address of the delta holder to fetch the delta for
    /// @return userBalance The user balance of the currency
    /// @return poolBalance The pool balance of the currency
    /// @return delta The delta of the currency
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
