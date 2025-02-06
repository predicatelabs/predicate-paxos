// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {PaxosV4Hook} from "../src/PaxosV4Hook.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

contract PredicateUniswapScript is Script, Constants {
    function setUp() public {}

    function run() public {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(POOLMANAGER);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(PaxosV4Hook).creationCode, constructorArgs);

        vm.broadcast();
        PaxosV4Hook paxosV4Hook = new PaxosV4Hook{salt: salt}(IPoolManager(POOLMANAGER));
        require(address(paxosV4Hook) == hookAddress, "PaxosV4HookScript: hook address mismatch");
    }
}