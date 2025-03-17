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

    mapping(address => bool) public authorizedLPs;

    event AuthorizedLPAdded(address indexed lp);
    event AuthorizedLPRemoved(address indexed lp);

    constructor(
        IPoolManager _poolManager,
        ISimpleV4Router _router,
        address _serviceManager,
        string memory _policyID
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        _initPredicateClient(_serviceManager, _policyID);
        router = _router;
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
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
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

        BeforeSwapDelta delta = toBeforeSwapDelta(0, 0);

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (!authorizedLPs[msg.sender]) {
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

    function setPredicateManager(
        address _predicateManager
    ) external onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    function addAuthorizedLP(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            emit AuthorizedLPAdded(_lps[i]);
            authorizedLPs[_lps[i]] = true;
        }
    }

    function removeAuthorizedLP(
        address[] memory _lps
    ) external onlyOwner {
        for (uint256 i = 0; i < _lps.length; i++) {
            emit AuthorizedLPRemoved(_lps[i]);
            authorizedLPs[_lps[i]] = false;
        }
    }

    function isAuthorizedLP(
        address _lp
    ) external view returns (bool) {
        return authorizedLPs[_lp];
    }
}
