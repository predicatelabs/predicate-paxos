// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./TestStorage.sol";
import "../DummyToken.sol";
import {MetaCoin} from "../../../src/examples/MetaCoin.sol";

contract STMSetup is TestStorage {
    MetaCoin public metaCoinContract;

    function setUp() public {
        vm.startPrank(owner);
        eigenPodManager = new MockEigenPodManager();
        strategyManager = new MockStrategyManager();

        delegationManagerAdmin = new MockProxyAdmin(owner);
        delegationManagerImplementation =
            new MockDelegationManager(address(strategyManager), slasher, address(eigenPodManager));
        delegationManager = MockDelegationManager(
            address(new MockProxy(address(delegationManagerImplementation), address(delegationManagerAdmin)))
        );
        delegationManager.initialize(address(this), IPauserRegistry(pauserRegistry), 0, 0);

        stakeRegistry = new MockStakeRegistry();
        serviceManagerAdmin = new MockProxyAdmin(owner);
        serviceManagerImplementation = new ServiceManager();
        serviceManager =
            ServiceManager(address(new MockProxy(address(serviceManagerImplementation), address(serviceManagerAdmin))));
        serviceManager.initialize(
            address(this),
            aggregator,
            address(delegationManager),
            address(stakeRegistry),
            address(delegationManager), // TODO WE MUST MOCK THE AVS REGISTRY CONTACT
            0
        );
        vm.stopPrank();

        vm.startPrank(address(this));
        serviceManager.deployPolicy(
            "testPolicy",
            '{"version":"1.0.0","name":"testPolicy","rules":[{"id":"membership-check-sg-1","effect":"deny", "predicate_id":"membership", "predicate_params":{"social_graph_id": "sg_1"}}],"consensus": {"broadcast": "all", "threshold": "1"}}',
            1
        );
        vm.stopPrank();

        (operatorOne, operatorOnePk) = makeAddrAndKey("operatorOne");
        (operatorOneAlias, operatorOneAliasPk) = makeAddrAndKey("operatorOneAlias");
        (operatorTwo, operatorTwoPk) = makeAddrAndKey("operatorTwo");
        (operatorTwoAlias, operatorTwoAliasPk) = makeAddrAndKey("operatorTwoAlias");

        (testSender, testSenderPk) = makeAddrAndKey("testSender");
        (testReceiver, testReceiverPk) = makeAddrAndKey("testReceiver");

        vm.startPrank(testSender);
        metaCoinContract = new MetaCoin(testSender, address(serviceManager), "testPolicy");
        ownableClientInterface = Ownable(address(metaCoinContract));
        vm.stopPrank();
    }
}
