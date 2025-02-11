// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { Deployers } from "v4-core/test/utils/Deployers.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { PoolSwapTest } from "v4-core/src/test/PoolSwapTest.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { BalanceDelta } from "v4-core/src/types/BalanceDelta.sol";
import { SafeCast } from "v4-core/src/libraries/SafeCast.sol";
import { Constants } from "v4-core/test/utils/Constants.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";
import { PaxosHook } from "src/PaxosHook.sol";

import "forge-std/console2.sol";

contract PaxosHookTest is Test, Deployers {
    using SafeCast for *;

    address hook;
    address user = address(0xBEEF);

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }
}