// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../common/INetwork.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISimpleV4Router} from "../../src/interfaces/ISimpleV4Router.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract Local is INetwork {
    function config() external pure override returns (Config memory) {
        return Config({
            poolManager: IPoolManager(address(0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6)),
            router: ISimpleV4Router(address(0x8A791620dd6260079BF849Dc5567aDC3F2FdC318)),
            positionManager: PositionManager(payable(address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0))), // not used
            permit2: IAllowanceTransfer(address(0x1f98407aaB862CdDeF78Ed252D6f557aA5b0f00d)), // not used
            create2Deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C),
            serviceManager: address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0),
            policyId: "local-test-policy"
        });
    }

    function liquidityPoolConfig() external pure override returns (LiquidityPoolConfig memory) {
        // note: this is not used right now
        return LiquidityPoolConfig({
            token0: address(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            token1: address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -600,
            tickUpper: 600,
            startingPrice: 79_228_162_514_264_337_593_543_950_336,
            token0Amount: 1e18,
            token1Amount: 1e18
        });
    }

    // note: this is not used right now
    function hookConfig() external pure override returns (HookConfig memory) {
        return HookConfig({hookContract: address(0xB88D683B9959c2A10f9d1A000A12a94EA8260080)});
    }

    // note: this is not used right now
    function tokenConfig() external pure override returns (TokenConfig memory) {
        return TokenConfig({
            USDL: Currency.wrap(address(0x6B175474E89094C44Da98b954EedeAC495271d0F)),
            wUSDL: Currency.wrap(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)),
            USDC: Currency.wrap(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2))
        });
    }
}
