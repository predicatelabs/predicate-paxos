// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {INetwork} from "./INetwork.sol";
import {NetworkSelector} from "./NetworkSelector.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

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
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(config.poolManager, config.ybsAddress, config.poolKey);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(config.create2Deployer, flags, type(AutoWrapper).creationCode, constructorArgs);
        console.log("Deploying AutoWrapper at address: ", hookAddress);
        vm.startBroadcast();
        AutoWrapper autoWrapper =
            new AutoWrapper{salt: salt}(config.poolManager, ERC4626(config.ybsAddress), config.poolKey);
        require(address(autoWrapper) == hookAddress, "AutoWrapper address does not match expected address");
        console.log("AutoWrapper deployed at: ", address(autoWrapper));
        vm.stopBroadcast();
    }
}
