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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Predicated Hook
 * @author Predicate Labs
 * @notice A hook for compliant swaps
 * @dev This hook validates transactions against defined policies, authorizes liquidity providers and users to bypass checks,
 *      and allows the owner to configure policies and manage the predicate manager
 */
contract PredicateHook is BaseHook, PredicateClient, Ownable {
    /**
     * @notice An error emitted when a liquidity provider is not authorized
     */
    error UnauthorizedLiquidityProvider();

    /**
     * @notice An error emitted when a transaction is not authorized by predicate
     */
    error PredicateAuthorizationFailed();

    /**
     * @notice An error emitted when a pool fee is not valid
     */
    error InvalidPoolFee();

    /**
     * @notice The router contract that is used to swap tokens
     * @dev This is the router contract is used to get the msgSender() who initiated the swap
     */
    ISimpleV4Router public router;

    /**
     * @notice A mapping of authorized liquidity providers
     * @dev This is used to check if the liquidity provider is authorized to add liquidity to the pool
     */
    mapping(address => bool) public isAuthorizedLP;

    /**
     * @notice A mapping of authorized users
     * @dev This is used to check if the user is authorized to swap tokens
     */
    mapping(address => bool) public isAuthorizedUser;

    /**
     * @notice An event emitted when a liquidity provider is added to the authorized lp list
     * @param lp The address of the liquidity provider
     */
    event AuthorizedLPAdded(address indexed lp);

    /**
     * @notice An event emitted when a liquidity provider is removed from the authorized lp list
     * @param lp The address of the liquidity provider
     */
    event AuthorizedLPRemoved(address indexed lp);

    /**
     * @notice An event emitted when a user is added to the authorized user list
     * @param user The address of the user
     */
    event AuthorizedUserAdded(address indexed user);

    /**
     * @notice An event emitted when a user is removed from the authorized user list
     * @param user The address of the user
     */
    event AuthorizedUserRemoved(address indexed user);

    /**
     * @notice Constructor for the PredicateHook
     * @param _poolManager The pool manager contract
     * @param _router The router contract
     * @param _serviceManager The service manager contract
     * @param _policyID The policy ID
     * @param _owner The owner of the contract
     */
    constructor(
        IPoolManager _poolManager,
        ISimpleV4Router _router,
        address _serviceManager,
        string memory _policyID,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        _initPredicateClient(_serviceManager, _policyID);
        router = _router;
        isAuthorizedLP[_owner] = true;
        isAuthorizedUser[_owner] = true;
    }

    /**
     * @notice Defines which hook callbacks are active for this contract
     * @return Permissions struct with beforeSwap enabled
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
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
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0);

        // If the sender is authorized, bypass the predicate check
        if (isAuthorizedUser[router.msgSender()]) {
            return (IHooks.beforeSwap.selector, delta, 0);
        }

        // If the sender is an authorized user, bypass the predicate check
        if (isAuthorizedUser[sender]) {
            return (IHooks.beforeSwap.selector, delta, 0);
        }

        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) =
            (this.decodeHookData(hookData), router.msgSender(), 0);

        bytes memory encodeSigAndArgs = abi.encodeWithSignature(
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)",
            msgSender,
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            address(key.hooks),
            params.zeroForOne,
            params.amountSpecified,
            params.sqrtPriceLimitX96
        );

        if (!_authorizeTransaction(predicateMessage, encodeSigAndArgs, msgSender, msgValue)) {
            revert PredicateAuthorizationFailed();
        }

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /**
     * @notice Validates transactions against the authorized liquidity providers before allowing add liquidity
     * @dev If the sender or router.msgSender() is not an authorized liquidity provider, the transaction will revert
     * @param sender The address initiating the liquidity addition
     * @param key Pool configuration information
     * @param params Modify liquidity parameters
     * @param hookData Encoded authorization data from the Predicate service
     * @return selector The function selector indicating success
     */
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        // If the sender is an authorized liquidity provider, bypass the check
        if (isAuthorizedLP[sender]) {
            return BaseHook.beforeAddLiquidity.selector;
        }

        // If the router.msgSender() is a liquidity provider, check if the sender is an authorized liquidity provider
        if (isAuthorizedLP[router.msgSender()]) {
            return BaseHook.beforeAddLiquidity.selector;
        }

        // If the sender is not an authorized liquidity provider, the transaction will revert
        revert UnauthorizedLiquidityProvider();
    }

    /**
     * @notice Utility to decode hook data into its components
     * @dev Extracts the authorization message from encoded hook data
     * @param hookData The encoded hook data from the swap call
     * @return predicateMessage The Predicate authorization message with signatures
     */
    function decodeHookData(
        bytes calldata hookData
    ) external pure returns (PredicateMessage memory) {
        PredicateMessage memory predicateMessage = abi.decode(hookData, (PredicateMessage));
        return predicateMessage;
    }

    /**
     * @notice Sets the policy ID
     * @param _policyID The new policy ID
     */
    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    /**
     * @notice Sets the predicate manager
     * @param _predicateManager The new predicate manager
     */
    function setPredicateManager(
        address _predicateManager
    ) external onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    /**
     * @notice Sets the router
     * @param _router The new router
     */
    function setRouter(
        ISimpleV4Router _router
    ) external onlyOwner {
        router = _router;
    }

    /**
     * @notice Adds authorized liquidity providers
     * @param _lps The addresses of the liquidity providers to add
     */
    function addAuthorizedLPs(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            isAuthorizedLP[_lps[i]] = true;
            emit AuthorizedLPAdded(_lps[i]);
        }
    }

    /**
     * @notice Removes authorized liquidity providers
     * @param _lps The addresses of the liquidity providers to remove
     */
    function removeAuthorizedLPs(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            isAuthorizedLP[_lps[i]] = false;
            emit AuthorizedLPRemoved(_lps[i]);
        }
    }

    /**
     * @notice Adds authorized users for swaps to skip the predicate check
     * @param _users The addresses of the users to add
     */
    function addAuthorizedUsers(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedUser[_users[i]] = true;
            emit AuthorizedUserAdded(_users[i]);
        }
    }

    /**
     * @notice Removes authorized users for swaps to skip the predicate check
     * @param _users The addresses of the users to remove
     */
    function removeAuthorizedUsers(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedUser[_users[i]] = false;
            emit AuthorizedUserRemoved(_users[i]);
        }
    }
}
