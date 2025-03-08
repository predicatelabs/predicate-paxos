// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {
    toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {BaseTokenWrapperHook} from "./base/BaseTokenWrapperHook.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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

    /// @notice Creates a new ERC4626 wrapper hook
    /// @param _manager The Uniswap V4 pool manager
    /// @param _vault The ERC4626 vault contract address
    /// @dev Initializes with the ERC4626 vault as wrapper token and the ERC4626 underlying asset as underlying token
    constructor(
        IPoolManager _manager,
        ERC4626 _vault,
        PoolKey memory _predicatePoolKey,
        ISimpleV4Router _router
    )
        BaseTokenWrapperHook(
            _manager,
            Currency.wrap(address(_vault)), // wrapper token is the ERC4626 vault itself
            Currency.wrap(address(_vault.asset())) // underlying token is the underlying asset of ERC4626 vault i.e. USDL
        )
    {
        vault = _vault;
        ERC20(Currency.unwrap(underlyingCurrency)).approve(address(vault), type(uint256).max);
        predicatePoolKey = _predicatePoolKey;
        router = _router;
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
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            IERC20(Currency.unwrap(underlyingCurrency)).transferFrom(router.msgSender(), address(this), inputAmount);
            // todo: settle balance delta from poolManager.swap

            (,, int256 deltaBefore0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
            (,, int256 deltaBefore1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));
            require(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
            require(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

            BalanceDelta delta = poolManager.swap(predicatePoolKey, params, hookData);

            // TODO: use DeltaResolver and Permit2Payments to settle balances
            (,, int256 deltaAfter0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
            (,, int256 deltaAfter1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));

            if (deltaAfter0 < 0) {
                underlyingCurrency.settle(poolManager, router.msgSender(), uint256(-deltaAfter0), false);
            }
            if (deltaAfter1 < 0) {
                underlyingCurrency.settle(poolManager, router.msgSender(), uint256(-deltaAfter1), false);
            }
            if (deltaAfter0 > 0) {
                underlyingCurrency.take(poolManager, router.msgSender(), uint256(deltaAfter0), false);
            }
            if (deltaAfter1 > 0) {
                underlyingCurrency.take(poolManager, router.msgSender(), uint256(deltaAfter1), false);
            }

            uint256 redeemAmount = _withdraw(inputAmount);
            _settle(underlyingCurrency, address(this), redeemAmount);
            int128 amountUnspecified =
                isExactInput ? -redeemAmount.toInt256().toInt128() : inputAmount.toInt256().toInt128();
            swapDelta = toBeforeSwapDelta(-params.amountSpecified.toInt128(), amountUnspecified);
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
