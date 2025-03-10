// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {DeltaResolver} from "@uniswap/v4-periphery/src/base/DeltaResolver.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title Base Token Wrapper Hook
/// @notice Abstract base contract for implementing token wrapper hooks in Uniswap V4
/// @notice Copied from https://github.com/Uniswap/v4-periphery/blob/main/src/base/hooks/BaseTokenWrapperHook.sol
/// @notice Modified to remove beforeInitialize hook and make it compatible with ERC4626 vaults and ghost pools
/// @dev This contract provides the base functionality for wrapping/unwrapping tokens through V4 pools
/// @dev All liquidity operations are blocked as liquidity is managed through the underlying token wrapper
/// @dev Implementing contracts must provide deposit() and withdraw() functions
abstract contract BaseTokenWrapperHook is BaseHook {
    /// @notice Thrown when attempting to add or remove liquidity
    /// @dev Liquidity operations are blocked since all liquidity is managed by the token wrapper
    error LiquidityNotAllowed();

    /// @notice Thrown when initializing a pool with non-zero fee
    /// @dev Fee must be 0 as wrapper pools don't charge fees
    error InvalidPoolFee();

    /// @notice The wrapped token currency (e.g., WETH)
    Currency public immutable wrapperCurrency;

    /// @notice The underlying token currency (e.g., ETH)
    Currency public immutable underlyingCurrency;

    /// @notice Indicates whether wrapping occurs when swapping from token0 to token1
    /// @dev This is determined by the relative ordering of the wrapper and underlying tokens
    /// @dev If true: token0 is underlying (e.g. ETH) and token1 is wrapper (e.g. WETH)
    /// @dev If false: token0 is wrapper (e.g. WETH) and token1 is underlying (e.g. ETH)
    /// @dev This is set in the constructor based on the token addresses to ensure consistent behavior
    bool public immutable wrapZeroForOne;

    /// @notice Creates a new token wrapper hook
    /// @param _manager The Uniswap V4 pool manager
    /// @param _wrapper The wrapped token currency (e.g., WETH)
    /// @param _underlying The underlying token currency (e.g., ETH)
    constructor(IPoolManager _manager, Currency _wrapper, Currency _underlying) BaseHook(_manager) {
        wrapperCurrency = _wrapper;
        underlyingCurrency = _underlying;
        wrapZeroForOne = _underlying < _wrapper;
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

    /// @notice Deposits underlying tokens to receive wrapper tokens
    /// @dev Implementing contracts should handle the wrapping operation
    /// @dev The base contract will handle settling tokens with the pool manager
    /// @param underlyingAmount The amount of underlying tokens to deposit
    /// @return wrappedAmount The amount of wrapper tokens received
    function _deposit(
        uint256 underlyingAmount
    ) internal virtual returns (uint256 wrappedAmount);

    /// @notice Withdraws wrapper tokens to receive underlying tokens
    /// @dev Implementing contracts should handle the unwrapping operation
    /// @dev The base contract will handle settling tokens with the pool manager
    /// @param wrappedAmount The amount of wrapper tokens to withdraw
    /// @return underlyingAmount The amount of underlying tokens received
    function _withdraw(
        uint256 wrappedAmount
    ) internal virtual returns (uint256 underlyingAmount);

    /// @notice Calculates underlying tokens needed to receive desired wrapper tokens
    /// @dev Default implementation assumes 1:1 ratio
    /// @dev Override for wrappers with different exchange rates
    /// @param wrappedAmount The desired amount of wrapper tokens
    /// @return The required amount of underlying tokens
    function _getWrapInputRequired(
        uint256 wrappedAmount
    ) internal view virtual returns (uint256);

    /// @notice Calculates wrapper tokens needed to receive desired underlying tokens
    /// @dev Default implementation assumes 1:1 ratio
    /// @dev Override for wrappers with different exchange rates
    /// @param underlyingAmount The desired amount of underlying tokens
    /// @return The required amount of wrapper tokens
    function _getUnwrapInputRequired(
        uint256 underlyingAmount
    ) internal view virtual returns (uint256);
}
