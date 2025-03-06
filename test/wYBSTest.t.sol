// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {YBSV1_1} from "src/paxos/YBSV1_1.sol";
import {wYBSV1} from "src/paxos/wYBSV1.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract wYBSV1Test is Test {
    YBSV1_1 public ybsImpl;
    wYBSV1 public wYbsImpl;
    YBSV1_1 public ybs;
    wYBSV1 public wYbs;

    address public admin;
    address public supplyController;
    address public pauser;
    address public assetProtector;
    address public rebaserAdmin;
    address public rebaser;
    address public user;

    uint256 public initialSupply = 1000 * 10**18; // 1000 tokens

    function setUp() public {
        admin = makeAddr("admin");
        supplyController = makeAddr("supplyController");
        pauser = makeAddr("pauser");
        assetProtector = makeAddr("assetProtector");
        rebaserAdmin = makeAddr("rebaserAdmin");
        rebaser = makeAddr("rebaser");
        user = makeAddr("user");

        // Deploy implementation contracts
        ybsImpl = new YBSV1_1();
        wYbsImpl = new wYBSV1();

        // Deploy YBS proxy with explicit initialization
        bytes memory ybsData = abi.encodeWithSelector(
            YBSV1_1.initialize.selector,
            "Yield Bearing Stablecoin",
            "YBS",
            18,
            admin,
            supplyController,
            pauser,
            assetProtector,
            rebaserAdmin,
            rebaser
        );

        ERC1967Proxy ybsProxy = new ERC1967Proxy(
            address(ybsImpl),
            ybsData
        );
        ybs = YBSV1_1(address(ybsProxy));

        bytes memory wYbsData = abi.encodeWithSelector(
            wYBSV1.initialize.selector,
            "Wrapped YBS",
            "wYBS",
            IERC20Upgradeable(address(ybs)),
            admin,
            pauser,
            assetProtector
        );

        ERC1967Proxy wYbsProxy = new ERC1967Proxy(
            address(wYbsImpl),
            wYbsData
        );
        wYbs = wYBSV1(address(wYbsProxy));

        // Grant WRAPPED_YBS_ROLE to wYBS contract - ensure we're using the admin role
        bytes32 role = ybs.WRAPPED_YBS_ROLE();
        vm.startPrank(admin);
        ybs.grantRole(role, address(wYbs));
        vm.stopPrank();

        // Mint YBS to supply controller
        vm.startPrank(supplyController);
        ybs.increaseSupply(initialSupply);

        // Transfer to test user
        ybs.transfer(user, initialSupply);
        vm.stopPrank();
    }

    function testDepositYBS() public {
        uint256 depositAmount = 100 * 10**18; // 100 tokens

        vm.startPrank(user);
        ybs.approve(address(wYbs), depositAmount);

        uint256 ybsBalanceBefore = ybs.balanceOf(user);
        uint256 wYbsBalanceBefore = wYbs.balanceOf(user);

        uint256 sharesReceived = wYbs.deposit(depositAmount, user);

        uint256 ybsBalanceAfter = ybs.balanceOf(user);
        uint256 wYbsBalanceAfter = wYbs.balanceOf(user);
        vm.stopPrank();

        assertEq(ybsBalanceBefore - ybsBalanceAfter, depositAmount, "YBS not transferred correctly");
        assertEq(wYbsBalanceAfter - wYbsBalanceBefore, sharesReceived, "wYBS shares not received correctly");
        assertEq(sharesReceived, depositAmount, "Expected 1:1 exchange rate for first deposit");

        assertEq(ybs.balanceOf(address(wYbs)), depositAmount, "Vault should hold deposited YBS");
    }
}