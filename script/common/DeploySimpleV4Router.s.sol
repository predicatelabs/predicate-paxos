// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {SimpleV4Router} from "../../src/SimpleV4Router.sol";

contract DeploySimpleV4Router is Script {
    INetwork private _env;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        if (networkExists) {
            require(networkExists, "All environment variables must be set if any are specified");
            string memory _network = vm.envString("NETWORK");
            _env = new NetworkSelector().select(_network);
        } else {
            _env = new NetworkSelector().select("LOCAL");
            console.log("No network specified. Defaulting to LOCAL.");
        }
    }

    function run() public {
        _init();
        INetwork.Config memory config = _env.config();
        IPoolManager manager = config.poolManager;

        vm.startBroadcast();
        SimpleV4Router router = new SimpleV4Router(manager);
        console.log("SimpleV4Router deployed at: ", address(router));
        vm.stopBroadcast();
    }
}
