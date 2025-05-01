// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutoWrapper} from "../src/AutoWrapper.sol";
import {AutoWrapperSetup} from "./utils/AutoWrapperSetup.sol";
import {V4Router} from "@uniswap/v4-periphery/src/V4Router.sol";
import {Test} from "forge-std/Test.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

contract AutoWrapperTest is Test, AutoWrapperSetup {
    using SafeCast for uint256;
    using SafeCast for int256;

    address public liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        _setUpHooksAndPools(liquidityProvider);
        require(autoWrapper.baseCurrencyIsToken0() == true, "baseCurrency is token0");
        require(autoWrapper.baseCurrencyIsToken0ForLiquidPool() == false, "baseCurrency is not token0 for liquid pool");
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("new-owner");
        address currentOwner = autoWrapper.owner();

        vm.prank(currentOwner);
        autoWrapper.transferOwnership(newOwner);
        assertEq(autoWrapper.pendingOwner(), newOwner);
        assertEq(autoWrapper.owner(), currentOwner);

        vm.prank(newOwner);
        autoWrapper.acceptOwnership();
        assertEq(autoWrapper.owner(), newOwner);
        assertEq(autoWrapper.pendingOwner(), address(0));
    }

    function testTransferOwnershipNotOwner() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", makeAddr("not-owner")));
        autoWrapper.transferOwnership(newOwner);
    }

    function testAcceptOwnershipNotPendingOwner() public {
        address newOwner = makeAddr("new-owner");
        address notNewOwner = makeAddr("not-new-owner");

        vm.prank(autoWrapper.owner());
        autoWrapper.transferOwnership(newOwner);

        vm.prank(notNewOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notNewOwner));
        autoWrapper.acceptOwnership();
    }

    function testSetRouter() public {
        address newRouter = makeAddr("new-router");
        vm.prank(autoWrapper.owner());
        autoWrapper.setRouter(V4Router(newRouter));
        assertEq(address(autoWrapper.router()), newRouter);
    }

    function testSetRouterNotOwner() public {
        address newRouter = makeAddr("new-router");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        autoWrapper.setRouter(V4Router(newRouter));
    }
}
