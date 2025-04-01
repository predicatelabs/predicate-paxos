// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../common/INetwork.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";

contract Local is INetwork {
    address public constant USDL = address(0xb185E9f6531BA9877741022C92CE858cDCc5760E);
    address public constant WUSDL = address(0x742489F22807ebB4C36ca6cD95c3e1C044B7B6c8);
    address public constant USDC = address(0xA9e6Bfa2BF53dE88FEb19761D9b2eE2e821bF1Bf);

    function config() external pure override returns (Config memory) {
        return Config({
            poolManager: IPoolManager(address(0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6)),
            positionManager: PositionManager(payable(address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0))), // not used
            permit2: IAllowanceTransfer(address(0x1f98407aaB862CdDeF78Ed252D6f557aA5b0f00d)), // not used
            create2Deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C),
            serviceManager: address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0)
        });
    }

    function tokenConfig() external pure override returns (TokenConfig memory) {
        return TokenConfig({USDL: Currency.wrap(USDL), wUSDL: Currency.wrap(WUSDL), USDC: Currency.wrap(USDC)});
    }
}
