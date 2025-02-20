// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

interface INetwork {
    struct Config {
        IPoolManager poolManager;
        address create2Deployer;
        address serviceManager;
        string policyId;
    }

    function config() external view returns (Config memory);
}
