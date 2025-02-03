// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.12;

import "forge-std/Test.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {MockClient} from "./helpers/MockClient.sol";
import "./helpers/utility/ServiceManagerSetup.sol";
import "forge-std/Test.sol";

contract OwnershipClientTest is ServiceManagerSetup {
    function test_OwnerIsOwnerByDefault() public {
        assertTrue(address(owner) == ownableClientInterface.owner());
    }

    function test_RandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(44));
        ownableClientInterface.transferOwnership(address(33));
    }
}

contract OwnershipServiceManagerTest is ServiceManagerSetup {
    function test_OwnerIsUninitializedFromConstructor() public {
        ServiceManager scopedServiceManager = new ServiceManager();
        Ownable ownableSM = Ownable(address(scopedServiceManager));
        assertTrue(address(0) == ownableSM.owner());
    }

    function test_OwnerIsChangedDuringSetup() public {
        Ownable ownableSM = Ownable(address(serviceManager));
        assertTrue(address(this) == ownableSM.owner());
    }

    function test_RandomAccountCannotTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(44));
        ownableServiceManagerInterface.transferOwnership(address(33));
    }
}
