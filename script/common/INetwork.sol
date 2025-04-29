// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

interface INetwork {
    struct Config {
        IPoolManager poolManager;
        PositionManager positionManager;
        IAllowanceTransfer permit2;
        address create2Deployer;
        address serviceManager;
        Currency baseCurrency;
        address wUSDL;
    }

    struct TokenConfig {
        Currency USDL;
        Currency wUSDL;
        Currency USDC; // USDC
    }

    function config() external view returns (Config memory);
    function tokenConfig() external view returns (TokenConfig memory);
}
