// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../common/INetwork.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract Local is INetwork {
    function config() external pure override returns (Config memory) {
        return Config({
            poolManager: IPoolManager(address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853)),
            create2Deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C),
            serviceManager: address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0),
            policyId: "strict-membership-policy"
        });
    }
}
