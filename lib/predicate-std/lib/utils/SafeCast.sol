// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
///         Adapted from UniswapV3: https://github.com/Uniswap/uniswap-v3-core/blob/v1.0.0/contracts/libraries/SafeCast.sol
library SafeCast {
    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint128
    function toUint128(uint256 y) internal pure returns (uint128 z) {
        require((z = uint128(y)) == y, "SafeCast: value doesn't fit in 128 bits");
    }

    /// @notice Cast a uint256 to a uint32, revert on overflow
    /// @param y The uint256 to be downcasted
    /// @return z The downcasted integer, now type uint32
    function toUint32(uint256 y) internal pure returns (uint32 z) {
        require((z = uint32(y)) == y, "SafeCast: value doesn't fit in 32 bits");
    }
}
