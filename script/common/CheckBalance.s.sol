// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract CheckBalance is Script {
    function run() public {
        vm.startBroadcast();
        MockERC20 token = MockERC20(address(0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82));
        address sender = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        console.log("Token balance for address", address(token), "is", token.balanceOf(sender));
        vm.stopBroadcast();
    }
}
