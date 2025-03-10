// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {BaseTokenWrapperHook} from "./base/BaseTokenWrapperHook.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title USDL Auto Wrapper Hook
 * @author Predicate Labs
 * @notice Uniswap V4 hook implementing an automatic wrapper/unwrapper for USDL and wUSDL
 * @dev This contract extends BaseTokenWrapperHook to provide a conversion between the yield bearing
 *      Lift Dollar (USDL) and its wrapped version (wUSDL) through a V4 Ghost pool.
 */
contract AutoWrapper is BaseTokenWrapperHook {
    using SafeCast for uint256;
    using SafeCast for int256;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    /// @notice The ERC4626 vault contract
    ERC4626 public immutable vault;

    /// @notice The predicate pool key
    PoolKey public predicatePoolKey;

    /// @notice The V4 router
    ISimpleV4Router public router;

    /// @notice USDC
    IERC20 public usdc;

    /// @notice Creates a new ERC4626 wrapper hook
    /// @param _manager The Uniswap V4 pool manager
    /// @param _vault The ERC4626 vault contract address
    /// @dev Initializes with the ERC4626 vault as wrapper token and the ERC4626 underlying asset as underlying token
    constructor(
        IPoolManager _manager,
        ERC4626 _vault,
        PoolKey memory _predicatePoolKey,
        ISimpleV4Router _router,
        IERC20 _usdc
    )
        BaseTokenWrapperHook(
            _manager,
            Currency.wrap(address(_vault)), // wrapper token is the ERC4626 vault itself
            Currency.wrap(address(_vault.asset())) // underlying token is the underlying asset of ERC4626 vault i.e. USDL
        )
    {
        vault = _vault;
        ERC20(Currency.unwrap(underlyingCurrency)).approve(address(vault), type(uint256).max);
        ERC20(Currency.unwrap(underlyingCurrency)).approve(address(this), type(uint256).max);
        predicatePoolKey = _predicatePoolKey;
        router = _router;
        usdc = _usdc;
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

        if (wrapZeroForOne == params.zeroForOne) {
            // we are wrapping
            // USDC -> USDL
            // case 1. I wanna swap 10 USDC to x USDL
            // case 2. I wanna swap x USDC to 10 USDL
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            usdc.transferFrom(router.msgSender(), address(this), inputAmount); // USDC -> this

            (,, int256 deltaBefore0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
            (,, int256 deltaBefore1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));

            BalanceDelta delta = poolManager.swap(predicatePoolKey, params, hookData); // USDC/WUSDL pool

            (,, int256 deltaAfter0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
            (,, int256 deltaAfter1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));

            if (deltaAfter0 < 0) {
                _settle(predicatePoolKey.currency0, poolManager, router.msgSender(), uint256(-deltaAfter0));
            }
            if (deltaAfter1 < 0) {
                _settle(predicatePoolKey.currency1, poolManager, router.msgSender(), uint256(-deltaAfter1));
            }
            if (deltaAfter0 > 0) {
                _take(predicatePoolKey.currency0, poolManager, router.msgSender(), uint256(deltaAfter0));
            }
            if (deltaAfter1 > 0) {
                _take(predicatePoolKey.currency1, poolManager, router.msgSender(), uint256(deltaAfter1));
            }
            // todo: calculation here
            uint256 redeemAmount = _withdraw(IERC20(Currency.unwrap(wrapperCurrency)).balanceOf(address(this)));
            IERC20(Currency.unwrap(underlyingCurrency)).transfer(router.msgSender(), redeemAmount);
        } else {
            // we are unwrapping
            // USDL -> USDC
            uint256 inputAmount = isExactInput
                ? uint256(-params.amountSpecified)
                : _getUnwrapInputRequired(uint256(params.amountSpecified));
            wrapperCurrency.transfer(address(this), inputAmount);
            uint256 wrappedAmount = _deposit(inputAmount);
            // todo: settle balance delta from poolManager.swap
            BalanceDelta delta = poolManager.swap(predicatePoolKey, params, hookData);
            _settle(wrapperCurrency, address(this), wrappedAmount);
            int128 amountUnspecified =
                isExactInput ? -wrappedAmount.toInt256().toInt128() : inputAmount.toInt256().toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
        }

        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Wraps assets to shares in the ERC4626 vault
    /// @param underlyingAmount Amount of assets to wrap
    /// @return Amount of shares received
    function _deposit(
        uint256 underlyingAmount
    ) internal override returns (uint256) {
        return vault.deposit({assets: underlyingAmount, receiver: address(this)});
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Unwraps shares to assets in the ERC4626 vault
    /// @param wrappedAmount Amount of shares to unwrap
    /// @return Amount of assets received
    function _withdraw(
        uint256 wrappedAmount
    ) internal override returns (uint256) {
        return vault.redeem({shares: wrappedAmount, receiver: address(this), owner: address(this)});
    }

    /// @inheritdoc BaseTokenWrapperHook
    function _getWrapInputRequired(
        uint256 wrappedAmount
    ) internal view override returns (uint256) {
        return vault.convertToAssets({shares: wrappedAmount});
    }

    /// @inheritdoc BaseTokenWrapperHook
    function _getUnwrapInputRequired(
        uint256 underlyingAmount
    ) internal view override returns (uint256) {
        return vault.convertToShares({assets: underlyingAmount});
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

    /// @notice Settle (pay) a currency to the PoolManager
    /// @param currency Currency to settle
    /// @param manager IPoolManager to settle to
    /// @param payer Address of the payer, the token sender
    /// @param amount Amount to send
    function _settle(Currency currency, IPoolManager manager, address payer, uint256 amount) internal {
        manager.sync(currency);
        if (payer != address(this)) {
            IERC20(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
        } else {
            IERC20(Currency.unwrap(currency)).transfer(address(manager), amount);
        }
        manager.settle();
    }

    /// @notice Take (receive) a currency from the PoolManager
    /// @param currency Currency to take
    /// @param manager IPoolManager to take from
    /// @param recipient Address of the recipient, the token receiver
    /// @param amount Amount to receive
    function _take(Currency currency, IPoolManager manager, address recipient, uint256 amount) internal {
        manager.take(currency, recipient, amount);
    }
}
