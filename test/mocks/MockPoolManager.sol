// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencyReserves} from "@uniswap/v4-core/src/libraries/CurrencyReserves.sol";
import {IProtocolFees} from "@uniswap/v4-core/src/interfaces/IProtocolFees.sol";
import {IERC6909Claims} from "@uniswap/v4-core/src/interfaces/external/IERC6909Claims.sol";
import {IExtsload} from "@uniswap/v4-core/src/interfaces/IExtsload.sol";
import {IExttload} from "@uniswap/v4-core/src/interfaces/IExttload.sol";
import {Pool} from "@uniswap/v4-core/src/libraries/Pool.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract MockPoolManager {
    using CurrencyReserves for Currency;

    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    address public protocolFeeController;

    error InvalidCaller();
    error ProtocolFeeCurrencySynced();

    mapping(PoolId id => Pool.State) internal _pools;
    bool internal _unlocked;

    function _isUnlocked() internal view returns (bool) {
        return _unlocked;
    }

    function _getPool(
        PoolId id
    ) internal view returns (Pool.State storage) {
        return _pools[id];
    }

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external pure returns (int24 tick) {
        return 0;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) external pure returns (BalanceDelta) {
        return toBalanceDelta(0, 0);
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta callerDelta, BalanceDelta feesAccrued) {
        return (toBalanceDelta(0, 0), toBalanceDelta(0, 0));
    }

    function donate(
        PoolKey memory key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external returns (BalanceDelta) {
        return toBalanceDelta(0, 0);
    }

    // function take(Currency currency, address to, uint256 amount) external {
    // }

    // function sync(Currency currency) external {
    // }

    // function settle() external payable returns (uint256) {
    //     return 0;
    // }

    // function settleFor(address recipient) external payable returns (uint256) {
    //     return 0;
    // }

    // function clear(Currency currency, uint256 amount) external {
    // }

    // function mint(address to, uint256 id, uint256 amount) external {
    // }

    // function burn(address from, uint256 id, uint256 amount) external {
    // }

    // function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external {
    // }

    // function setProtocolFeeController(address controller) external {
    // }

    // function unlock(bytes calldata data) external returns (bytes memory) {
    //     return "";
    // }

    // function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
    // }

    // function balanceOf(address owner, uint256 id) external view returns (uint256) {
    //     return 0;
    // }

    // function allowance(address owner, address spender, uint256 id) external view returns (uint256) {
    //     return 0;
    // }

    // function isOperator(address owner, address operator) external view returns (bool) {
    //     return false;
    // }

    // function transfer(address to, uint256 id, uint256 amount) external returns (bool) {
    //     return true;
    // }

    // function transferFrom(address from, address to, uint256 id, uint256 amount) external returns (bool) {
    //     return true;
    // }

    // function approve(address spender, uint256 id, uint256 amount) external returns (bool) {
    //     return true;
    // }

    // function setOperator(address operator, bool approved) external returns (bool) {
    //     return true;
    // }

    // function extsload(bytes32 slot) external view returns (bytes32) {
    //     return bytes32(0);
    // }

    // function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory) {
    //     return new bytes32[](nSlots);
    // }

    // function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
    //     return new bytes32[](slots.length);
    // }

    // function exttload(bytes32 slot) external view returns (bytes32) {
    //     return bytes32(0);
    // }

    // function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
    //     return new bytes32[](slots.length);
    // }

    // function collectProtocolFees(address recipient, Currency currency, uint256 amount)
    //     external
    //     returns (uint256 amountCollected)
    // {
    //     if (msg.sender != protocolFeeController) revert InvalidCaller();
    //     if (!currency.isAddressZero() && CurrencyReserves.getSyncedCurrency() == currency) {
    //         revert ProtocolFeeCurrencySynced();
    //     }

    //     amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
    //     protocolFeesAccrued[currency] -= amountCollected;
    //     currency.transfer(recipient, amountCollected);
    // }
}
