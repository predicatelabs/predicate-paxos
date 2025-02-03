// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockProxyAdmin} from "./MockProxyAdmin.sol";

contract MockProxy is TransparentUpgradeableProxy {
    constructor(
        address _implementation,
        address _admin
    ) TransparentUpgradeableProxy(_implementation, _admin, bytes("")) {}
}
