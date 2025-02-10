// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {PredicateMessage} from "lib/predicate-std/src/interfaces/IPredicateClient.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {PredicateWrapper} from "../src/PredicateWrapper.sol";
import {MockPaxosV4Hook} from "./mocks/MockPaxosV4Hook.sol";
import {MockPredicateClient} from "./mocks/MockPredicateClient.sol";

contract PredicateWrapperTest is Test {
    IPoolManager public _poolManager = IPoolManager(address(0x00B036B58a818B1BC34d502D3fE730Db729e62AC));

    PredicateWrapper public wrapper;
    MockPaxosV4Hook public mockPaxosHook;
    MockPredicateClient public mockPredicateClient;

    address public serviceManager = address(0xf6f4A30EeF7cf51Ed4Ee1415fB3bFDAf3694B0d2);
    string public defaultPolicyID = "Policy-123";
    address public deployer = address(this);

    PoolKey public poolKey;
    IPoolManager.SwapParams public swapParams;
    bytes public validHookData;
    bytes public invalidHookData;

    function setUp() public {
        mockPaxosHook = new MockPaxosV4Hook(_poolManager);
        mockPredicateClient = new MockPredicateClient();

        wrapper = new PredicateWrapper(
            serviceManager,
            defaultPolicyID,
            address(mockPaxosHook)
        );

        poolKey = PoolKey({
            currency0: Currency.wrap(address(1)),
            currency1: Currency.wrap(address(2)),
            fee: 3000,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1000,
            sqrtPriceLimitX96: 0
        });

        PredicateMessage memory pm = PredicateMessage({
            taskId: "test-task",
            expireByBlockNumber: block.number + 25,
            signerAddresses: new address[](0),
            signatures: new bytes[](0)
        });
        validHookData = abi.encode(pm, address(this), 0);

        invalidHookData = abi.encode(pm, address(this), 0);
    }

    /// @notice Tests a successful call to beforeSwap where authorization is granted.
    function testBeforeSwapAuthorized() public {
        mockPredicateClient.setAuthorized(true);

        (bytes4 selector, BeforeSwapDelta swapDelta, uint24 fee) =
            wrapper.beforeSwap(
                address(this),
                poolKey,
                swapParams,
                validHookData
            );

        bytes4 expectedSelector = bytes4(keccak256("MockBeforeSwap()"));
        assertEq(selector, expectedSelector, "Incorrect selector returned");

        int128 specified = BeforeSwapDeltaLibrary.getSpecifiedDelta(swapDelta);
        int128 unspecified = BeforeSwapDeltaLibrary.getUnspecifiedDelta(swapDelta);
        assertEq(specified, 100, "Incorrect swapDelta.delta0");
        assertEq(unspecified, 200, "Incorrect swapDelta.delta1");

        assertEq(fee, 300, "Incorrect fee returned");
    }

    function testBeforeSwapUnauthorized() public {
        mockPredicateClient.setAuthorized(false);

        vm.expectRevert(bytes("Unauthorized transaction"));

        wrapper.beforeSwap(
            address(this),
            poolKey,
            swapParams,
            invalidHookData
        );
    }

    function testSetPolicy() public {
        string memory newPolicyID = "Policy-699";
        wrapper.setPolicy(newPolicyID);

        vm.recordLogs();
        wrapper.setPolicy(newPolicyID);
        Vm.Log[] memory entries = vm.getRecordedLogs();
    }

    function testSetPredicateManager() public {
        address newManager = address(0xBB);

        wrapper.setPredicateManager(newManager);
    }

    function testSetPaxosV4Hook() public {
        MockPaxosV4Hook newMockHook = new MockPaxosV4Hook(_poolManager);

        address oldHook = address(wrapper.paxosV4Hook());
        assertEq(oldHook, address(mockPaxosHook), "Initial Paxos hook mismatch");

        wrapper.setPaxosV4Hook(address(newMockHook));

        address updatedHook = address(wrapper.paxosV4Hook());
        assertEq(updatedHook, address(newMockHook), "New Paxos hook mismatch");
    }
}
