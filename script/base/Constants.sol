// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "lib/v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";

contract Constants {
    address public immutable CREATE2_DEPLOYER;
    IPoolManager public immutable POOLMANAGER;
    PositionManager public immutable POSM;
    IAllowanceTransfer public immutable PERMIT2;

    constructor(
        address _create2Deployer,
        address _poolManager,
        address _posm,
        address _permit2
    ) {
        require(_create2Deployer != address(0), "Invalid CREATE2 Deployer");
        require(_poolManager != address(0), "Invalid PoolManager");
        require(_posm != address(0), "Invalid PositionManager");
        require(_permit2 != address(0), "Invalid Permit2");

        CREATE2_DEPLOYER = _create2Deployer;
        POOLMANAGER = IPoolManager(_poolManager);
        POSM = PositionManager(payable(_posm));
        PERMIT2 = IAllowanceTransfer(_permit2);
    }
}
