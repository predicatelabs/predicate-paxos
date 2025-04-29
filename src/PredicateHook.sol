// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PredicateClient} from "@predicate/mixins/PredicateClient.sol";
import {PredicateMessage} from "@predicate/interfaces/IPredicateClient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";

/**
 * @title Predicated v4 Hook
 * @author Predicate Labs
 * @notice This contract requires an offchain integration with predicate.io to authorize transactions before they are submitted onchain
 * @dev Users of this hook are required to pass in a valid Predicate authorization message within the hookData field.
 */
contract PredicateHook is BaseHook, PredicateClient, Ownable2Step {
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
     * @notice An error emitted when the pool being initialized does not match the expected configuration
     */
    error InvalidPoolConfiguration();

    /**
     * @notice The router contract that is used to swap tokens
     * @dev This router contract is used to get the msgSender() who initiated the swap
     */
    V4Router public router;

    /**
     * @notice The position manager contract
     * @dev This contract is used to manage positions on the pool
     */
    PositionManager public posm;

    /**
     * @notice The base currency for this liquid pool
     */
    Currency public immutable baseCurrency;

    /**
     * @notice The wrapped USDL token
     */
    address public immutable wUSDL;

    /**
     * @notice A mapping of authorized liquidity providers
     * @dev Used to check if the liquidity provider is authorized to add liquidity to the pool
     */
    mapping(address => bool) public isAuthorizedLP;

    /**
     * @notice A mapping of end users who are authorized to bypass the predicate check
     * @dev Used to bypass the predicate check for certain users
     */
    mapping(address => bool) public isAuthorizedSwapper;

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
     * @notice Event emitted when the policy ID is updated
     * @param policyID The new policy ID
     */
    event PolicyUpdated(string policyID);

    /**
     * @notice Event emitted when the predicate manager is updated
     * @param predicateManager The new predicate manager address
     */
    event PredicateManagerUpdated(address predicateManager);

    /**
     * @notice Event emitted when the router is updated
     * @param router The new router address
     */
    event RouterUpdated(address router);

    /**
     * @notice Constructor for the PredicateHook
     * @param _poolManager The pool manager contract
     * @param _posm The position manager contract
     * @param _router The router contract
     * @param _serviceManager The service manager contract
     * @param _policyID The policy ID
     * @param _owner The owner of the contract
     * @param _baseCurrency The base currency for the liquid pool
     * @param _wUSDL The wrapped USDL token address
     */
    constructor(
        IPoolManager _poolManager,
        PositionManager _posm,
        V4Router _router,
        address _serviceManager,
        string memory _policyID,
        address _owner,
        Currency _baseCurrency,
        address _wUSDL
    ) BaseHook(_poolManager) Ownable(_owner) {
        _initPredicateClient(_serviceManager, _policyID);
        router = _router;
        posm = _posm;
        baseCurrency = _baseCurrency;
        wUSDL = _wUSDL;
        isAuthorizedLP[_owner] = true;
        isAuthorizedSwapper[_owner] = true;
        emit PolicyUpdated(_policyID);
        emit PredicateManagerUpdated(_serviceManager);
        emit RouterUpdated(address(_router));
        emit AuthorizedLPAdded(_owner);
        emit AuthorizedUserAdded(_owner);
    }

    /**
     * @notice Defines which hook callbacks are active for this contract
     * @return Permissions struct with beforeInitialize, beforeAddLiquidity, and beforeSwap enabled
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
     * @notice Validates pool initialization parameters for the underlying pool
     * @dev Ensures the pool being initialized matches the expected liquid pool configuration
     * @param poolKey The pool configuration being initialized
     * @return The function selector if validation passes
     */
    function _beforeInitialize(address, PoolKey calldata poolKey, uint160) internal view override returns (bytes4) {
        if (poolKey.fee != 0) revert InvalidPoolFee();
        bool hasBaseCurrency = poolKey.currency0 == baseCurrency || poolKey.currency1 == baseCurrency;
        bool hasWUSDL = poolKey.currency0 == Currency.wrap(wUSDL) || poolKey.currency1 == Currency.wrap(wUSDL);
        if (!hasBaseCurrency || !hasWUSDL) revert InvalidPoolConfiguration();
        return IHooks.beforeInitialize.selector;
    }

    /**
     * @notice Validates transactions against the defined policy before allowing swaps
     * @dev Extracts the Predicate authorization message and validates its authenticity against the Predicate Service Manager
     * @param sender The address of the sender
     * @param key Underlying pool configuration information
     * @param params Swap parameters including direction and amount
     * @param hookData Encoded authorization message from Predicate
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
        BeforeSwapDelta delta = BeforeSwapDelta.wrap(0);

        // If the end user is authorized, bypass the predicate check
        if (sender == address(router) && isAuthorizedSwapper[router.msgSender()]) {
            return (IHooks.beforeSwap.selector, delta, 0);
        }

        PredicateMessage memory predicateMessage = abi.decode(hookData, (PredicateMessage));

        bytes memory encodeSigAndArgs = abi.encodeWithSignature(
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256)",
            router.msgSender(),
            key.currency0,
            key.currency1,
            key.fee,
            key.tickSpacing,
            address(key.hooks),
            params.zeroForOne,
            params.amountSpecified
        );

        if (!_authorizeTransaction(predicateMessage, encodeSigAndArgs, router.msgSender(), 0)) {
            revert PredicateAuthorizationFailed();
        }

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /**
     * @notice Validates transactions against the authorized liquidity providers before allowing add liquidity
     * @dev If the sender or posm.msgSender() is not an authorized liquidity provider, the transaction will revert
     * @dev This is to prevent unauthorized liquidity providers from adding liquidity to the pool
     * @param sender The address of the sender
     * @return selector The function selector indicating success
     */
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        // If the sender is the position manager and the msgSender is an authorized liquidity provider, allow the transaction
        if (sender == address(posm) && isAuthorizedLP[posm.msgSender()]) {
            return BaseHook.beforeAddLiquidity.selector;
        }

        // If the sender is an authorized liquidity provider, allow the transaction
        if (isAuthorizedLP[sender]) {
            return BaseHook.beforeAddLiquidity.selector;
        }

        // If the sender is not an authorized liquidity provider, the transaction will revert
        revert UnauthorizedLiquidityProvider();
    }

    /**
     * @notice Sets the policy ID read by Predicate Operators
     * @param _policyID The new policy ID
     */
    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
        emit PolicyUpdated(_policyID);
    }

    /**
     * @notice Sets the predicate manager used to authorize transactions
     * @param _predicateManager The new predicate manager
     */
    function setPredicateManager(
        address _predicateManager
    ) external onlyOwner {
        _setPredicateManager(_predicateManager);
        emit PredicateManagerUpdated(_predicateManager);
    }

    /**
     * @notice Sets the router contract used to get the msgSender()
     * @param _router The new router
     */
    function setRouter(
        V4Router _router
    ) external onlyOwner {
        router = _router;
        emit RouterUpdated(address(_router));
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
     * @notice Adds authorized swappers for swaps to bypass the predicate check
     * @param _users The addresses of the swappers to add
     */
    function addAuthorizedSwapper(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedSwapper[_users[i]] = true;
            emit AuthorizedUserAdded(_users[i]);
        }
    }

    /**
     * @notice Removes authorized swappers from the list
     * @param _users The addresses of the swappers to remove
     */
    function removeAuthorizedSwapper(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedSwapper[_users[i]] = false;
            emit AuthorizedUserRemoved(_users[i]);
        }
    }
}
