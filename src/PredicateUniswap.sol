// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

contract PredicateUniswap is BaseHook {
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        (Currency inputCurrency, Currency outputCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        bool isExactInput = params.amountSpecified < 0;

        uint256 amount = isExactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        poolManager.mint(address(this), inputCurrency.toId(), amount);

        poolManager.burn(address(this), outputCurrency.toId(), amount);

        int128 tokenAmount = amount.toInt128();
        BeforeSwapDelta returnDelta =
            isExactInput ? toBeforeSwapDelta(tokenAmount, -tokenAmount) : toBeforeSwapDelta(-tokenAmount, tokenAmount);

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("No v4 Liquidity allowed");
    }

    /// @notice Add liquidity 1:1 for the constant sum curve
    /// @param key PoolKey of the pool to add liquidity to
    /// @param amountPerToken The amount of each token to be added as liquidity
    function addLiquidity(PoolKey calldata key, uint256 amountPerToken) external {
        poolManager.unlock(abi.encode(msg.sender, key.currency0, key.currency1, amountPerToken));
    }

    function _unlockCallback(bytes calldata data) internal virtual override returns (bytes memory) {
        (address payer, Currency currency0, Currency currency1, uint256 amountPerToken) =
            abi.decode(data, (address, Currency, Currency, uint256));

        poolManager.sync(currency0);
        IERC20(Currency.unwrap(currency0)).transferFrom(payer, address(poolManager), amountPerToken);
        poolManager.settle();

        poolManager.sync(currency1);
        IERC20(Currency.unwrap(currency1)).transferFrom(payer, address(poolManager), amountPerToken);
        poolManager.settle();

        poolManager.mint(address(this), currency0.toId(), amountPerToken);
        poolManager.mint(address(this), currency1.toId(), amountPerToken);

        return "";
    }
}
