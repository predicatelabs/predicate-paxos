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
    address public constant SWAP_ROUTER = address(0x0cb9d2172864d965eF693915bee403a040b7410D); //todo: udpate this
    address public constant POSITION_MANAGER = address(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    address public constant PERMIT2 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address public constant SERVICE_MANAGER = address(0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2);
    address public constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    address public constant USDe = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant YBS_ADDRESS = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant USDC = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function config() external pure override returns (Config memory) {
        return Config({
            poolManager: IPoolManager(POOL_MANAGER),
            router: ISimpleV4Router(SWAP_ROUTER),
            positionManager: PositionManager(payable(POSITION_MANAGER)),
            permit2: IAllowanceTransfer(PERMIT2),
            create2Deployer: CREATE2_DEPLOYER,
            serviceManager: SERVICE_MANAGER,
            policyId: "x-aleo-6a52de9724a6e8f2",
            ybsAddress: YBS_ADDRESS,
            poolKey: PoolKey({
                currency0: Currency.wrap(USDe),
                currency1: Currency.wrap(DAI),
                fee: 3000,
                tickSpacing: 60,
                hooks: IHooks(address(0))
            }),
            usdc: USDC
        });
    }

    function poolConfig() external pure override returns (PoolConfig memory) {
        return PoolConfig({
            token0: USDe,
            token1: DAI,
            fee: 3000,
            tickSpacing: 60,
            tickLower: -600,
            tickUpper: 600,
            startingPrice: 79_228_162_514_264_337_593_543_950_336,
            token0Amount: 50e18,
            token1Amount: 50e18
        });
    }

    function hookConfig() external pure override returns (HookConfig memory) {
        return HookConfig({hookContract: address(0x57Df5778B93ab56CEEF966311EBeEcd295918080)});
    }
}
