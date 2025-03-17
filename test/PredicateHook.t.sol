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

    function testSetPolicyUnauthorized() public {
        string memory newPolicy = "new-policy";
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.setPolicy(newPolicy);
    }

    function testSetPredicateManager() public {
        address newManager = makeAddr("new-manager");
        vm.prank(hook.owner());
        hook.setPredicateManager(newManager);
        assertEq(hook.getPredicateManager(), newManager);
    }

    function testSetPredicateManagerUnauthorized() public {
        address newManager = makeAddr("new-manager");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.setPredicateManager(newManager);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("new-owner");
        vm.prank(hook.owner());
        hook.transferOwnership(newOwner);
        assertEq(hook.owner(), newOwner);
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

    function testAddAuthorizedLPUnauthorized() public {
        address[] memory lps = new address[](1);
        lps[0] = liquidityProvider;
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.addAuthorizedLPs(lps);
    }

    function testAddAuthorizedUser() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(hook.owner());
        hook.addAuthorizedUsers(users);
        assertEq(hook.isAuthorizedUser(users[0]), true);
    }

    function testRemoveAuthorizedUser() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(hook.owner());
        hook.addAuthorizedUsers(users);
        assertEq(hook.isAuthorizedUser(users[0]), true);

        vm.prank(hook.owner());
        hook.removeAuthorizedUsers(users);
        assertEq(hook.isAuthorizedUser(users[0]), false);
    }

    function testAddAuthorizedUserUnauthorized() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.addAuthorizedUsers(users);
    }

    function testRemoveAuthorizedUserUnauthorized() public {
        address[] memory users = new address[](1);
        users[0] = makeAddr("user");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.removeAuthorizedUsers(users);
    }

    function testSetRouter() public {
        address newRouter = makeAddr("new-router");
        vm.prank(hook.owner());
        hook.setRouter(ISimpleV4Router(newRouter));
        assertEq(address(hook.router()), newRouter);
    }

    function testSetRouterUnauthorized() public {
        address newRouter = makeAddr("new-router");
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        hook.setRouter(ISimpleV4Router(newRouter));
    }
}
