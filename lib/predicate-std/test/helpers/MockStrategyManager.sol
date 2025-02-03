// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

import {IStrategy} from "./eigenlayer/interfaces/IStrategy.sol";

contract MockStrategyManager {
    function getDeposits(
        address
    ) external pure returns (IStrategy[] memory, uint256[] memory) {
        IStrategy[] memory strategyManagerStrats = new IStrategy[](0);
        uint256[] memory strategyManagerShares = new uint256[](0);
        return (strategyManagerStrats, strategyManagerShares);
    }
}
