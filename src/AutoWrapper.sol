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
import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";

/**
 * @title USDL Auto Wrapper Hook
 * @author Predicate Labs
 * @notice Uniswap V4 hook implementing an automatic wrapper/unwrapper for USDL and wUSDL
 * @dev This contract extends BaseTokenWrapperHook to provide a conversion between the yield bearing
 *      Lift Dollar (USDL) and its wrapped version (wUSDL) through a V4 Ghost pool.
 * @dev This contract also implements DeltaResolver to handle the token delta settlement
 */
contract AutoWrapper is BaseTokenWrapperHook, DeltaResolver {
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
            Currency.wrap(address(_vault)), // wrapper token is the ERC4626 vault itself // WUSDL
            Currency.wrap(address(_vault.asset())) // underlying token is the underlying asset of ERC4626 vault i.e. USDL
        )
    {
        vault = _vault;
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
        IPoolManager.SwapParams memory swapParams = params;

        if (wrapZeroForOne == params.zeroForOne) {
            // USDC -> USDL
            uint256 inputAmount =
                isExactInput ? uint256(-params.amountSpecified) : _getWrapInputRequired(uint256(params.amountSpecified));
            usdc.transferFrom(router.msgSender(), address(this), inputAmount);
            swapParams.amountSpecified = isExactInput ? -int256(inputAmount) : int256(inputAmount);
            _swap(swapParams, hookData);
            uint256 redeemAmount = _withdraw(IERC20(Currency.unwrap(wrapperCurrency)).balanceOf(address(this)));
            //todo: use balance Delta for settle and return delta
            IERC20(Currency.unwrap(underlyingCurrency)).transfer(router.msgSender(), redeemAmount);
        } else {
            // USDL -> USDC
            int256 inputAmount = params.amountSpecified;
            if (isExactInput) {
                IERC20(Currency.unwrap(underlyingCurrency)).transferFrom(
                    router.msgSender(), address(this), uint256(-params.amountSpecified)
                );
                uint256 wrappedAmount = _deposit(uint256(-params.amountSpecified));
                swapParams.amountSpecified = -int256(wrappedAmount);
            }
            _swap(swapParams, hookData);
            //todo: use balance Delta for settle and return delta
            uint256 usdcBalance = usdc.balanceOf(address(this));
            usdc.transfer(router.msgSender(), usdcBalance);
        }
        return (IHooks.beforeSwap.selector, swapDelta, 0);
    }

    /// @notice Swaps through the underlying liquidity pool
    /// @dev This function is used to swap through the underlying liquidity pool and settle the token delta as well
    /// @param params The swap parameters
    /// @param hookData The hook data
    function _swap(IPoolManager.SwapParams memory params, bytes calldata hookData) internal {
        (,, int256 deltaBefore0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
        (,, int256 deltaBefore1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));
        require(deltaBefore0 == 0, "deltaBefore0 is not 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not 0");

        BalanceDelta delta = poolManager.swap(predicatePoolKey, params, hookData); // USDC/WUSDL pool
        // todo: check if can use delta directly

        (,, int256 deltaAfter0) = _fetchBalances(predicatePoolKey.currency0, router.msgSender(), address(this));
        (,, int256 deltaAfter1) = _fetchBalances(predicatePoolKey.currency1, router.msgSender(), address(this));

        if (deltaAfter0 < 0) {
            _settle(predicatePoolKey.currency0, address(this), uint256(-deltaAfter0));
        }
        if (deltaAfter1 < 0) {
            _settle(predicatePoolKey.currency1, address(this), uint256(-deltaAfter1));
        }
        if (deltaAfter0 > 0) {
            _take(predicatePoolKey.currency0, address(this), uint256(deltaAfter0));
        }
        if (deltaAfter1 > 0) {
            _take(predicatePoolKey.currency1, address(this), uint256(deltaAfter1));
        }
    }

    /// @inheritdoc DeltaResolver
    function _pay(Currency token, address, uint256 amount) internal override {
        token.transfer(address(poolManager), amount);
    }

    /// @inheritdoc BaseTokenWrapperHook
    function _deposit(
        uint256 underlyingAmount
    ) internal override returns (uint256) {
        return vault.deposit({assets: underlyingAmount, receiver: address(this)});
    }

    /// @inheritdoc BaseTokenWrapperHook
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
}
