// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {PredicateUniswap} from "../src/PredicateUniswap.sol";
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
            HookMiner.find(CREATE2_DEPLOYER, flags, type(PredicateUniswap).creationCode, constructorArgs);

        vm.broadcast();
        PredicateUniswap predicateUniswap = new PredicateUniswap{salt: salt}(IPoolManager(POOLMANAGER));
        require(address(predicateUniswap) == hookAddress, "PredicateUniswapScript: hook address mismatch");
    }
}