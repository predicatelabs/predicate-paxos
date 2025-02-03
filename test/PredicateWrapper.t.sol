// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CompliantUniswap} from "../src/CompliantUniswap.sol";

contract PredicateWrapperTest is Test {
    CompliantUniswap dex;

    function setUp() public {
        dex = new CompliantUniswap(dex);
    }
}