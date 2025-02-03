// SPDX-License-Indetifier: MIT

pragma solidity =0.8.12;

import {DelegationManager} from "./eigenlayer/DelegationManager.sol";
import {IStrategyManager} from "./eigenlayer/interfaces/IStrategyManager.sol";
import {ISlasher} from "./eigenlayer/interfaces/ISlasher.sol";
import {IEigenPodManager} from "./eigenlayer/interfaces/IEigenPodManager.sol";

contract MockDelegationManager is DelegationManager {
    constructor(
        address _strategyManager,
        address _slasher,
        address _eigenPodManager
    ) DelegationManager(IStrategyManager(_strategyManager), ISlasher(_slasher), IEigenPodManager(_eigenPodManager)) {}
}
