// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTokenWrapperHook} from "@uniswap/v4-periphery/src/base/hooks/BaseTokenWrapperHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {wYBSV1} from "./paxos/wYBSV1.sol";
import {IwYBSV1} from "./interfaces/IwYBSV1.sol";

import {IYBSV1_1} from "./interfaces/IYBSV1_1.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol"; // Added Currency

/// @title Auto Wrapper
/// @author Predicate Labs
/// @notice A hook for auto wrapping and unwrapping YBS, "USDL"
contract AutoWrapper is BaseTokenWrapperHook {
    /// @notice The wUSDL contract used for wrapping/unwrapping operations
    IwYBSV1 public immutable wUSDL;

    /// @notice The USDL contract
    IYBSV1_1 public immutable USDL;

    /// @notice Creates a new wUSDL wrapper hook
    /// @param _manager The Uniswap V4 pool manager
    /// @param _wUSDL The wUSDL contract address
    /// @dev Initializes with wUSDL as wrapper token and USDL as underlying token
    constructor(
        IPoolManager _manager,
        IwYBSV1 _wUSDL
    )
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

    // @inheritdoc BaseTokenWrapperHook
    /// @notice Wraps USDL to wUSDL
    /// @param underlyingAmount Amount of USDL to wrap
    /// @return Amount of wUSDL received
    function _deposit(
        uint256 underlyingAmount
    ) internal override returns (uint256) {
        return wUSDL.deposit(underlyingAmount, address(this));
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Unwraps wUSDL to USDL
    /// @param wrapperAmount Amount of wUSDL to unwrap
    /// @return Amount of USDL received
    function _withdraw(
        uint256 wrapperAmount
    ) internal override returns (uint256) {
        return wUSDL.redeem(wrapperAmount, address(this), address(this));
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Calculates how much USDL is needed to receive a specific amount of wUSDL
    /// @param wrappedAmount Desired amount of wUSDL
    /// @return Amount of USDL required
    /// @dev Uses current USDL/wUSDL exchange rate for calculation
    function _getWrapInputRequired(
        uint256 wrappedAmount
    ) internal view override returns (uint256) {
        return wUSDL.previewMint(wrappedAmount);
    }

    /// @inheritdoc BaseTokenWrapperHook
    /// @notice Calculates how much wUSDL is needed to receive a specific amount of USDL
    /// @param underlyingAmount Desired amount of USDL
    /// @return Amount of wUSDL required
    /// @dev Uses current USDL/wUSDL exchange rate for calculation
    function _getUnwrapInputRequired(
        uint256 underlyingAmount
    ) internal view override returns (uint256) {
        return wUSDL.previewWithdraw(underlyingAmount);
    }
}
