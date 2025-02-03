// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

contract MockStakeRegistry {
    struct StrategyParams {
        IStrategy strategy;
        uint96 multiplier;
    }

    // the addresses are the ones from the tests' mock strategy addresses
    function strategyParamsByIndex(uint8, uint256 index) external pure returns (StrategyParams memory) {
        if (index == 0) {
            return StrategyParams({strategy: IStrategy(0x584273A7D8F5B01898b0c609c0E2b6f5984f0605), multiplier: 1});
        }

        return StrategyParams({strategy: IStrategy(0x2c2e3c305116ec1963B00860224e9392637C4328), multiplier: 1});
    }
}
