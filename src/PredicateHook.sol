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

/// @title Predicated Hook
/// @author Predicate Labs
/// @notice A hook for compliant swaps
contract PredicateHook is BaseHook, PredicateClient, Ownable {
    ISimpleV4Router public immutable router;

    mapping(address => bool) public isAuthorizedLP;
    bool public byPassAuthorizedLPs;
    mapping(address => bool) public isAuthorizedUser;

    event AuthorizedLPAdded(address indexed lp);
    event AuthorizedLPRemoved(address indexed lp);
    event AuthorizedUserAdded(address indexed user);
    event AuthorizedUserRemoved(address indexed user);

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
        byPassAuthorizedLPs = false;
    }

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
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0);

        // If the sender is authorized, bypass the predicate check
        if (isAuthorizedUser[sender]) {
            return (IHooks.beforeSwap.selector, delta, 0);
        }

        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) = this.decodeHookData(hookData);

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

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (!isAuthorizedLP[router.msgSender()] && !byPassAuthorizedLPs) {
            revert("Unauthorized liquidity provider");
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function decodeHookData(
        bytes calldata hookData
    ) external pure returns (PredicateMessage memory, address, uint256) {
        (PredicateMessage memory predicateMessage, address msgSender, uint256 msgValue) =
            abi.decode(hookData, (PredicateMessage, address, uint256));

        return (predicateMessage, msgSender, msgValue);
    }

    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    function setByPassAuthorizedLPs(
        bool _byPassAuthorizedLPs
    ) external onlyOwner {
        byPassAuthorizedLPs = _byPassAuthorizedLPs;
    }

    function setPredicateManager(
        address _predicateManager
    ) external onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    function addAuthorizedLPs(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            isAuthorizedLP[_lps[i]] = true;
            emit AuthorizedLPAdded(_lps[i]);
        }
    }

    function removeAuthorizedLPs(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            isAuthorizedLP[_lps[i]] = false;
            emit AuthorizedLPRemoved(_lps[i]);
        }
    }

    function addAuthorizedUsers(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedUser[_users[i]] = true;
            emit AuthorizedUserAdded(_users[i]);
        }
    }

    function removeAuthorizedUsers(
        address[] memory _users
    ) external onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            isAuthorizedUser[_users[i]] = false;
            emit AuthorizedUserRemoved(_users[i]);
        }
    }
}
