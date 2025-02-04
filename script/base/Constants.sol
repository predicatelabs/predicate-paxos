// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "lib/v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Shared constants used in scripts
contract Constants {
    address constant create2Deployer = vm.envAddress("CREATE2_DEPLOYER");
    address constant poolManagerAddress= vm.envAddress("POOLMANAGER");
    address constant posmAddress = vm.envAddress("POSM");
    address constant permit2Address = vm.envAddress("PERMIT2");

    IPoolManager constant POOLMANAGER = IPoolManager(poolManagerAddress);
    PositionManager constant posm = PositionManager((payable(posmAddress)));
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(permit2Address);
}
