// SPDX-License-Identifier: MIT

pragma solidity =0.8.12;

import {IStrategy} from "./eigenlayer/interfaces/IStrategy.sol";

contract MockEigenPodManager {
    function podOwnerShares(
        address
    ) external pure returns (int256) {
        return 0;
    }

    function test() public {}
}
