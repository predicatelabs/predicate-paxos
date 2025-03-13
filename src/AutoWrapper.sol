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
     * @notice The ERC4626 vault used for wrapping/unwrapping USDL
     * @dev Enables the conversion between USDL and wUSDL
     */
    ERC4626 public immutable vault;

    /**
     * @notice The pool key for the liquid liquidity pool (ERC20/wUSDL)
     * @dev Used to execute actual swaps on the pool containing wUSDL and liquidity
     */
    PoolKey public predicatePoolKey;

    /**
     * @notice Reference to the router handling user swap requests
     * @dev Used to access the actual message sender. This is a trusted contract.
     */
    ISimpleV4Router public router;

    /**
     * @notice Reference to the exchange ERC20 token paired with USDL in the liquid pool
     * @dev Used for transfers between user, hook, and pools
     */
    IERC20 public exchangeToken;

    /**
     * @notice Currency object for the wrapped token (wUSDL)
     * @dev Used for pool operations on the liquid pool
     */
    Currency public immutable wUSDL;

    /**
     * @notice Currency object for the rebasing token (USDL)
     * @dev The rebasing token that users actually receive/send
     */
    Currency public immutable USDL;

    /**
     * @notice Indicates whether wrapping occurs when swapping from token0 to token1
     * @dev This is determined by the relative ordering of wUSDL and USDL
     * @dev If true: token0 is USDL and token1 is wUSDL
     * @dev If false: token0 is wUSDL and token1 is USDL
     * @dev This is set in the constructor based on the token addresses to ensure consistent behavior
     */
    bool public immutable wrapZeroForOne;

    /**
     * @notice Creates an AutoWrapper hook to bridge between ghost and a pre-liquid pool
     * @dev Validates token ordering between ghost and liquid pools, sets up token approvals,
     *      and establishes the relationship between pools for swap routing
     * @param _manager The Uniswap V4 pool manager
     * @param _vault The ERC4626 vault for USDL/wUSDL conversion
     * @param _predicatePoolKey The pool key for the liquid ERC20/wUSDL liquidity pool
     * @param _router The router handling user swap requests
     * @param _exchangeToken Reference to the exchange ERC20 token in the liquid ERC20/wUSDL pool
     */
    constructor(
        IPoolManager _manager,
        ERC4626 _vault,
        PoolKey memory _predicatePoolKey,
        ISimpleV4Router _router,
        IERC20 _exchangeToken
    ) BaseHook(_manager) {
        require(
            address(_exchangeToken) == Currency.unwrap(_predicatePoolKey.currency0),
            "the exchange token is not the same as the currency0 on the predicate pool"
        );
        require(
            address(_vault) == Currency.unwrap(_predicatePoolKey.currency1),
            "the wrapped token is not the same as the currency1 on the predicate pool"
        );
        vault = _vault;
        predicatePoolKey = _predicatePoolKey;
        router = _router;
        exchangeToken = _exchangeToken;
        wUSDL = Currency.wrap(address(_vault));
        USDL = Currency.wrap(_vault.asset());
        wrapZeroForOne = USDL < wUSDL;
        IERC20(Currency.unwrap(USDL)).approve(Currency.unwrap(wUSDL), type(uint256).max);
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
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4 selector, BeforeSwapDelta swapDelta, uint24 lpFeeOverride) {
        // Determine if this is an exact input swap (amountSpecified < 0) or exact output swap
        bool isExactInput = params.amountSpecified < 0;
        IPoolManager.SwapParams memory swapParams = params;
        BalanceDelta delta;

        if (wrapZeroForOne == params.zeroForOne) {
            // ERC20 -> USDL swap path

            // Adjust swap parameters based on swap type
            // For exact output swaps, calculate the wUSDL amount needed
            swapParams.amountSpecified =
                isExactInput ? params.amountSpecified : getUnwrapInputRequired(uint256(params.amountSpecified));

            // Execute the swap on the liquid pool (ERC20 -> wUSDL)
            delta = _swap(swapParams, hookData);

            // Process ERC20 token for settlement
            // Extract delta0 representing ERC20 tokens owed to the pool
            int256 delta0 = BalanceDeltaLibrary.amount0(delta);
            require(delta0 < 0, "ERC20 delta must be negative for ERC20 -> USDL swap");

            // Transfer ERC20 tokens from user to this contract for settlement
            exchangeToken.transferFrom(router.msgSender(), address(this), uint256(-delta0));

            // Settle all token balances with the pool manager
            _settleDelta(delta);

            // Unwrap tokens and deliver to user
            // Convert wUSDL to USDL
            uint256 redeemAmount = _withdraw(IERC20(Currency.unwrap(wUSDL)).balanceOf(address(this)));

            // Send USDL to the original sender
            IERC20(Currency.unwrap(USDL)).transfer(router.msgSender(), redeemAmount);
        } else {
            // USDL -> ERC20 swap path

            // Adjust swap parameters based on swap type
            // For exact input, calculate equivalent wUSDL amount
            swapParams.amountSpecified =
                isExactInput ? -getUnwrapInputRequired(uint256(-params.amountSpecified)) : params.amountSpecified;

            // Execute the swap on the liquid pool (wUSDL -> ERC20)
            delta = _swap(swapParams, hookData);
            uint256 USDLAmount;

            if (isExactInput) {
                // For exact input: User specifies exact USDL amount
                USDLAmount = uint256(-params.amountSpecified);

                // Transfer USDL from user to this contract
                IERC20(Currency.unwrap(USDL)).transferFrom(router.msgSender(), address(this), USDLAmount);
            } else {
                // For exact output: Calculate USDL needed based on wUSDL delta
                int256 delta1 = BalanceDeltaLibrary.amount1(delta);
                require(delta1 < 0, "wUSDL delta must be negative for USDL -> ERC20 swap");

                // Calculate USDL needed to create required wUSDL
                USDLAmount = uint256(getWrapInputRequired(uint256(-delta1)));

                // Transfer required USDL from user
                IERC20(Currency.unwrap(USDL)).transferFrom(router.msgSender(), address(this), USDLAmount);
            }

            // Wrap USDL to wUSDL for settlement
            _deposit(USDLAmount);

            // Settle all token balances with the pool manager
            _settleDelta(delta);

            // Transfer resulting ERC20 tokens to the user
            uint256 exchangeTokenBalance = exchangeToken.balanceOf(address(this));
            exchangeToken.transfer(router.msgSender(), exchangeTokenBalance);
        }

        // Return function selector, empty delta for ghost pool, and zero fee override
        // The actual swap occurs on the liquid pool where fees are charged
        return (IHooks.beforeSwap.selector, swapDelta, 0);
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

        delta = poolManager.swap(predicatePoolKey, params, hookData); // exchangeToken/wUSDL pool

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
        return vault.deposit({assets: USDLAmount, receiver: address(this)});
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
        return vault.redeem({shares: wUSDLAmount, receiver: address(this), owner: address(this)});
    }

    /**
     * @notice Calculates USDL required to obtain a desired amount of wUSDL
     * @param wUSDLAmount The target amount of wUSDL needed
     * @return wUSDL amount of USDL required
     */
    function getWrapInputRequired(
        uint256 wUSDLAmount
    ) public view returns (int256) {
        return int256(vault.convertToAssets({shares: wUSDLAmount}));
    }

    /**
     * @notice Calculates wUSDL required to obtain a desired amount of USDL
     * @param USDLAmount The target amount of USDL needed
     * @return The amount of wUSDL required
     */
    function getUnwrapInputRequired(
        uint256 USDLAmount
    ) public view returns (int256) {
        return int256(vault.convertToShares({assets: USDLAmount}));
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
