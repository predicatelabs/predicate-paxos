// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISimpleV4Router} from "./interfaces/ISimpleV4Router.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title PredicateHook
 * @author Predicate Labs
 * @notice A Uniswap V4 hook for policy-enforced swaps via the Predicate Network
 * @dev Implements transaction authorization by validating signatures from Predicate Network that are
 *      passed by the sender against defined policies before allowing swaps to proceed
 */
contract PredicateHook is BaseHook, PredicateClient {
    /**
     * @notice Reference to the router handling swap requests
     * @dev Used to determine the original message sender. This is a trusted contract.
     */
    ISimpleV4Router public immutable router;

    /**
     * @notice Creates a PredicateHook with required dependencies
     * @param _poolManager The Uniswap V4 pool manager
     * @param _router The router for accessing the original message sender
     * @param _serviceManager The Predicate service manager contract address
     * @param _policyID The initial policy identifier
     */
    constructor(
        IPoolManager _poolManager,
        ISimpleV4Router _router,
        address _serviceManager,
        string memory _policyID
    ) BaseHook(_poolManager) {
        _initPredicateClient(_serviceManager, _policyID);
        router = _router;
    }

    /**
     * @notice Defines which hook callbacks are active for this contract
     * @return Permissions struct with beforeSwap enabled
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Validates transactions against the defined policy before allowing swaps
     * @dev Extracts authorization data, encodes transaction parameters, and verifies
     *      signatures from the Predicate service against the current policy
     * @param key Pool configuration information
     * @param params Swap parameters including direction and amount
     * @param hookData Encoded authorization data from the Predicate service
     * @return selector The function selector indicating success
     * @return delta Empty delta for the pool
     * @return lpFeeOverride Fee override
     */
    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        (
            PredicateMessage memory predicateMessage,
            address msgSender, // todo remove this from the hook data
            uint256 msgValue
        ) = this.decodeHookData(hookData);

        bytes memory encodeSigAndArgs = abi.encodeWithSignature(
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)",
            router.msgSender(),
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            address(key.hooks),
            params.zeroForOne,
            params.amountSpecified,
            params.sqrtPriceLimitX96
        );

        require(
            _authorizeTransaction(predicateMessage, encodeSigAndArgs, msgSender, msgValue), "Unauthorized transaction"
        );

        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0);

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /**
     * @notice Updates the policy ID
     * @dev This policy ID is fetched by the Predicate Network
     * @param _policyID The new policy identifier
     */
    function setPolicy(
        string memory _policyID
    ) external {
        _setPolicy(_policyID);
    }

    /**
     * @notice Updates the Predicate manager contract address
     * @dev This contract maintains the Predicate Network Registry
     *     and is used to validate signatures
     * @param _predicateManager The new manager contract address
     */
    function setPredicateManager(
        address _predicateManager
    ) public {
        _setPredicateManager(_predicateManager);
    }

    /**
     * @notice Utility to decode hook data into its components
     * @dev Extracts the authorization message, sender, and value from encoded hook data
     * @param hookData The encoded hook data from the swap call
     * @return predicateMessage The Predicate authorization message with signatures
     * @return msgSender The original transaction sender
     * @return msgValue Any ETH value sent with the transaction
     */
    function decodeHookData(
        bytes calldata hookData
    ) external pure returns (PredicateMessage memory, address, uint256) {
        (
            PredicateMessage memory predicateMessage,
            address msgSender, // todo remove this from the hook data
            uint256 msgValue
        ) = abi.decode(hookData, (PredicateMessage, address, uint256));

        return (predicateMessage, msgSender, msgValue);
    }
}
