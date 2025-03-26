// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../common/INetwork.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract Mainnet is INetwork {
    address public constant POOL_MANAGER = address(0x000000000004444c5dc75cB358380D2e3dE08A90);
    address public constant POSITION_MANAGER = address(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    address public constant PERMIT2 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address public constant SERVICE_MANAGER = address(0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2);
    address public constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    address public constant USDL = address(0xbdC7c08592Ee4aa51D06C27Ee23D5087D65aDbcD);
    address public constant WUSDL = address(0x7751E2F4b8ae93EF6B79d86419d42FE3295A4559);
    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function config() external pure override returns (Config memory) {
        return Config({
            id: 0,
            poolManager: IPoolManager(POOL_MANAGER),
            positionManager: PositionManager(payable(POSITION_MANAGER)),
            permit2: IAllowanceTransfer(PERMIT2),
            create2Deployer: CREATE2_DEPLOYER,
            serviceManager: SERVICE_MANAGER
        });
    }

    function liquidityPoolConfig() external pure override returns (LiquidityPoolConfig memory) {
        return LiquidityPoolConfig({
            token0: WUSDL,
            token1: USDC,
            fee: 0,
            tickSpacing: 60,
            tickLower: -600,
            tickUpper: 600,
            startingPrice: 79_228_162_514_264_337_593_543,
            token0Amount: 5e18,
            token1Amount: 5e6
        });
    }

    function tokenConfig() external pure override returns (TokenConfig memory) {
        return TokenConfig({USDL: Currency.wrap(USDL), wUSDL: Currency.wrap(WUSDL), USDC: Currency.wrap(USDC)});
    }
}
