// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IYBSV1_1} from "./interfaces/IYBSV1_1.sol";
import {IwYBSV1} from "./interfaces/IwYBSV1.sol";
import {IPoolManager} from "@uniswap/v4-coresrc/interfaces/IPoolManager.sol";
import {IPoolManager} from "@uniswap/v4-coresrc/interfaces/IPoolManager.sol";
import {BaseTokenWrapperHook} from "@uniswap/v4-peripherysrc/base/hooks/BaseTokenWrapperHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/**
 * @title USDL Auto Wrapper Hook
 * @author Predicate Labs
 * @notice Uniswap V4 hook implementing an automatic wrapper/unwrapper for USDL and wUSDL
 * @dev This contract extends BaseTokenWrapperHook to provide a conversion between the yield bearing
 *      Lift Dollar (USDL) and its wrapped version (wUSDL) through a V4 Ghost pool.
 */
contract AutoWrapper is BaseTokenWrapperHook {
    /// @notice Reference to the wrapped USDL (wUSDL) contract, a non-rebasing wrapper for USDL
    IwYBSV1 public immutable wUSDL;

    /// @notice Reference to the underlying yield-bearing USDL contract
    IYBSV1_1 public immutable USDL;

    /**
     * @notice Constructs a new AutoWrapper hook
     * @param _manager The Uniswap V4 pool manager
     * @param _wUSDL The wUSDL contract address
     * @dev Sets up token approvals and inherits from BaseTokenWrapperHook with appropriate currency configurations.
     *      The order of currencies (wrapper/underlying) follows the same pattern as wstETH/stETH.
     */
    constructor(IPoolManager _manager, IwYBSV1 _wUSDL)
    BaseTokenWrapperHook(
    _manager,
    Currency.wrap(address(_wUSDL)), // wrapper token is wUSDL
    Currency.wrap(address(_wUSDL.asset())) // underlying token is USDL
    )
    {
        wUSDL = _wUSDL;
        USDL = IYBSV1_1(address(_wUSDL.asset()));
        ERC20(Currency.unwrap(underlyingCurrency)).approve(address(wUSDL), type(uint256).max);
    }

    /**
     * @inheritdoc BaseTokenWrapperHook
     * @dev Wraps yield-bearing USDL to non-rebasing wUSDL using the deposit function from ERC-4626.
     * @param underlyingAmount Amount of USDL to wrap
     * @return shares Amount of wUSDL tokens received, representing a share of the deposited USDL
     */
    function _deposit(uint256 underlyingAmount) internal override returns (uint256) {
        return wUSDL.deposit(underlyingAmount, address(this));
    }

    /**
     * @inheritdoc BaseTokenWrapperHook
     * @dev Unwraps wUSDL back to USDL using the redeem function from ERC-4626.
     * @param wrapperAmount Amount of wUSDL to unwrap
     * @return assets Amount of USDL tokens received
     */
    function _withdraw(uint256 wrapperAmount) internal override returns (uint256) {
        return wUSDL.redeem(wrapperAmount, address(this), address(this));
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Calculates how much USDL is needed to receive a specific amount of wUSDL
    /// @param wrappedAmount Desired amount of wUSDL
    /// @return Amount of USDL required
    /// @dev Uses current USDL/wUSDL exchange rate for calculation
    function _getWrapInputRequired(uint256 wrappedAmount) internal view override returns (uint256) {
        return wUSDL.previewMint(wrappedAmount);
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Calculates how much wUSDL is needed to receive a specific amount of USDL
    /// @param underlyingAmount Desired amount of USDL
    /// @return Amount of wUSDL required
    /// @dev Uses current USDL/wUSDL exchange rate for calculation
    function _getUnwrapInputRequired(uint256 underlyingAmount) internal view override returns (uint256) {
        return wUSDL.previewWithdraw(underlyingAmount);
    }
}
