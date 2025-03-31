// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PredicateHook} from "../src/PredicateHook.sol";
import {PredicateHookSetup} from "./utils/PredicateHookSetup.sol";
import {ISimpleV4Router} from "../src/interfaces/ISimpleV4Router.sol";

contract PredicateHookTest is PredicateHookSetup {
    address liquidityProvider;

    function setUp() public override {
        liquidityProvider = makeAddr("liquidityProvider");
        super.setUp();
        setUpPredicateHook(liquidityProvider);
    }

    function testSetPolicy() public {
        string memory newPolicy = "new-policy";
        vm.prank(hook.owner());
        hook.setPolicy(newPolicy);
        assertEq(hook.getPolicy(), newPolicy);
    }

    function testSetPolicyNotOwner() public {
        string memory newPolicy = "new-policy";
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.setPolicy(newPolicy);
    }

    function testSetPredicateManager() public {
        address newManager = makeAddr("new-manager");
        vm.prank(hook.owner());
        hook.setPredicateManager(newManager);
        assertEq(hook.getPredicateManager(), newManager);
    }

    function testSetPredicateManagerNotOwner() public {
        address newManager = makeAddr("new-manager");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.setPredicateManager(newManager);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("new-owner");
        address currentOwner = hook.owner();

        vm.prank(currentOwner);
        hook.transferOwnership(newOwner);
        assertEq(hook.pendingOwner(), newOwner);
        assertEq(hook.owner(), currentOwner);

        vm.prank(newOwner);
        hook.acceptOwnership();
        assertEq(hook.owner(), newOwner);
        assertEq(hook.pendingOwner(), address(0));
    }

    function testTransferOwnershipNotOwner() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", makeAddr("not-owner")));
        hook.transferOwnership(newOwner);
    }

    function testAcceptOwnershipNotPendingOwner() public {
        address newOwner = makeAddr("new-owner");
        address notNewOwner = makeAddr("not-new-owner");

        vm.prank(hook.owner());
        hook.transferOwnership(newOwner);

        vm.prank(notNewOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notNewOwner));
        hook.acceptOwnership();
    }

    function testAddAuthorizedLP() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(hook.owner());
        hook.addAuthorizedLPs(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), true);
    }

    function testRemoveAuthorizedLP() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(hook.owner());
        hook.addAuthorizedLPs(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), true);

        vm.prank(hook.owner());
        hook.removeAuthorizedLPs(lps);
        assertEq(hook.isAuthorizedLP(liquidityProvider), false);
    }

    function testAddAuthorizedLPNotOwner() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.addAuthorizedLPs(lps);
    }

    function testAddAuthorizedSwapper() public {
        address[] memory swappers = new address[](1);
        swappers[0] = makeAddr("swapper");
        vm.prank(hook.owner());
        hook.addAuthorizedSwapper(swappers);
        assertEq(hook.isAuthorizedSwapper(swappers[0]), true);
    }

    function testRemoveAuthorizedSwapper() public {
        address[] memory swappers = new address[](1);
        swappers[0] = makeAddr("swapper");
        vm.prank(hook.owner());
        hook.addAuthorizedSwapper(swappers);
        assertEq(hook.isAuthorizedSwapper(swappers[0]), true);

        vm.prank(hook.owner());
        hook.removeAuthorizedSwapper(swappers);
        assertEq(hook.isAuthorizedSwapper(swappers[0]), false);
    }

    function testAddUnauthorizedSwapperNotOwner() public {
        address[] memory swappers = new address[](1);
        swappers[0] = makeAddr("swapper");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.addAuthorizedSwapper(swappers);
    }

    function testRemoveAuthorizedSwapperNotOwner() public {
        address[] memory swappers = new address[](1);
        swappers[0] = makeAddr("swapper");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.removeAuthorizedSwapper(swappers);
    }

    function testSetRouter() public {
        address newRouter = makeAddr("new-router");
        vm.prank(hook.owner());
        hook.setRouter(ISimpleV4Router(newRouter));
        assertEq(address(hook.router()), newRouter);
    }

    function testSetRouterNotOwner() public {
        address newRouter = makeAddr("new-router");
        vm.prank(makeAddr("not-owner"));
        vm.expectRevert();
        hook.setRouter(ISimpleV4Router(newRouter));
    }
}
