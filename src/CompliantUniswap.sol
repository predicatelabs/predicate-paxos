// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "compliant-uniswap/lib/v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "compliant-uniswap/lib/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "compliant-uniswap/lib/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "compliant-uniswap/lib/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "compliant-uniswap/lib/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "compliant-uniswap/lib/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "compliant-uniswap/lib/v4-core/test/utils/CurrencySettler.sol";
import {BalanceDelta} from "compliant-uniswap/lib/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "compliant-uniswap/lib/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "compliant-uniswap/lib/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "compliant-uniswap/lib/v4-core/src/libraries/StateLibrary.sol";

import {PredicateWrapper} from "./PredicateWrapper.sol";

contract CompliantUniswap is BaseHook {

    address public owner;
    PredicateWrapper private _predicateWrapper;

    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using StateLibrary for IPoolManager;

    error PoolNotInitialized();
    error TickSpacingNotDefault();
    error LiquidityDoesntMeetMinimum();
    error SenderMustBeHook();
    error ExpiredPastDeadline();
    error TooMuchSlippage();
    error SwapsNotAllowed();

    event SwapAttemptBlocked(address sender, PoolKey key);
    event LiquidityAdded(address sender, uint256 amount0, uint256 amount1);

    mapping(PoolId => uint256) public poolInfo;

    // mapping(address => bool) public allowedLiquidityProviders;
    mapping(address => bool) public whitelist;

    constructor(
        IPoolManager _poolManager, 
        address _predicateWrapperAddress
    ) 
        BaseHook(_poolManager)
    {
        _predicateWrapper = PredicateWrapper(_predicateWrapperAddress);
        owner = msg.sender;
    }

    function setPredicateWrapper(address predicateWrapper) external {
        require(msg.sender == owner, "Not owner");
        _predicateWrapper = PredicateWrapper(predicateWrapper);
    }

    function isWhitelisted(address sender) public view returns (bool) {
        return whitelist[sender];
    }

    function updateWhitelist(address sender, bool status) public {
        require(msg.sender == owner, "Not owner");
        whitelist[sender] = status;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address sender, 
                        PoolKey calldata key, 
                        IPoolManager.SwapParams calldata params, 
                        bytes calldata data
                    ) public override returns (bytes4, BeforeSwapDelta, uint24) 
    {
        if (isWhitelisted(sender)) {
            (bytes4 sel, bytes memory hookData) = _predicateWrapper.beforeSwap(sender, key, params, data);
            return (sel, BeforeSwapDelta(0, 0), 0);
        }
        revert SwapsNotAllowed();
    }

    function afterSwap(address sender, 
                        PoolKey calldata key, 
                        IPoolManager.SwapParams calldata params, 
                        BalanceDelta delta,
                        bytes calldata data
                    ) public override returns (bytes4, int128)
    {
        if (isWhitelisted(sender)) {
            (bytes4 selector, int128 swapResult) = _predicateWrapper.afterSwap(sender, key, params, delta, data);
            return (selector, swapResult);
        }

        revert SwapsNotAllowed();
    }

    function beforeAddLiquidity(address sender, PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata params, bytes calldata data)
        public override returns (bytes4)
    {
        require(isWhitelisted(sender), "Sender not compliant");
        return _predicateWrapper.beforeAddLiquidity(sender, key, params, data);
    }

    function beforeRemoveLiquidity(
                                    address, 
                                    PoolKey calldata key, 
                                    IPoolManager.ModifyLiquidityParams calldata, 
                                    bytes calldata
                                ) public override returns (bytes4) 
    {
        return BaseHook.beforeRemoveLiquidity.selector;
    }
}