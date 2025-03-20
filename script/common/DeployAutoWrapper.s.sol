// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AutoWrapper} from "../../src/AutoWrapper.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

contract DeployAutoWrapper is Script {
    INetwork private _env;

    function _init() internal {
        bool networkExists = vm.envExists("NETWORK");
        if (networkExists) {
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
    }
}
