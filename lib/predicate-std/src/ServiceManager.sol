// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IPredicateManager, Task, SignatureWithSaltAndExpiry} from "./interfaces/IPredicateManager.sol";

contract ServiceManager is IPredicateManager, OwnableUpgradeable {
    error ServiceManager__Unauthorized();
    error ServiceManager__InvalidOperator();
    error ServiceManager__InvalidStrategy();
    error ServiceManager__ArrayLengthMismatch();

    enum OperatorStatus {
        NEVER_REGISTERED, // default is NEVER_REGISTERED
        REGISTERED,
        DEREGISTERED
    }

    struct OperatorInfo {
        uint256 totalStake;
        OperatorStatus status;
    }

    mapping(address => OperatorInfo) public operators;
    mapping(address => address) public signingKeyToOperator;
    mapping(address => mapping(string => bool)) public clientToPolicy;
    mapping(string => string) public idToPolicy;
    mapping(string => bool) public spentTaskIds;
    mapping(string => string) public idToSocialGraph;

    string[] public deployedPolicyIDs;
    string[] public socialGraphIDs;

    address[] public strategies;
    address public aggregator;
    address public delegationManager;
    address public stakeRegistry;
    address public avsDirectory;
    uint256 public thresholdStake;

    mapping(string => uint256) policyIdToThreshold;
    mapping(address => bool) private permissionedOperators;

    event SetPolicy(address indexed client, string indexed policyID);
    event DeployedPolicy(string indexed policyID, string policy);
    event RemovedPolicy(address indexed client, string indexed policyID);
    event OperatorRegistered(address indexed operator);
    event OperatorRemoved(address indexed operator);
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event TaskExecuted(bytes32 indexed taskHash);
    event OperatorsStakesUpdated(address[][] indexed operatorsPerQuorum, bytes indexed quorumNumbers);
    event NonCompliantTask(uint256 indexed taskID);
    event AggregatorUpdated(address indexed aggregator);
    event AVSDirectoryUpdated(address indexed avsDirectory);
    event ThresholdStakeUpdated(uint256 indexed thresholdStake);
    event DelegationManagerUpdated(address indexed delegationManager);
    event StakeRegistryUpdated(address indexed stakeRegistry);
    event SocialGraphDeployed(string indexed socialGraphID, string socialGraphConfig);
    event TaskValidated(
        address indexed msgSender,
        address indexed target,
        uint256 indexed value,
        string policyID,
        string taskId,
        uint32 quorumThresholdCount,
        uint256 expireByBlockNumber,
        address[] signerAddresses
    );

    modifier onlyAggregator() {
        if (msg.sender != aggregator) {
            revert ServiceManager__Unauthorized();
        }
        _;
    }

    modifier onlyPermissionedOperator() {
        if (!permissionedOperators[msg.sender]) {
            revert ServiceManager__Unauthorized();
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _aggregator,
        address _delegationManager,
        address _stakeRegistry,
        address _avsDirectory,
        uint256 _thresholdStake
    ) external initializer {
        _transferOwnership(_owner);
        aggregator = _aggregator;
        delegationManager = _delegationManager;
        stakeRegistry = _stakeRegistry;
        avsDirectory = _avsDirectory;
        thresholdStake = _thresholdStake;
    }

    /**
     * @notice Sets the aggregator address on contracts
     * @param _aggregator is the aggregator that can execute the callback
     * @dev only callable by the owner
     */
    function setAggregator(
        address _aggregator
    ) external onlyOwner {
        aggregator = _aggregator;
        emit AggregatorUpdated(aggregator);
    }

    /**
     * @notice Sets the delegationManager contract address
     * @param _delegationManager is the delegationManager on the eigenlayer contracts
     * @dev only callable by the owner
     */
    function setDelegationManager(
        address _delegationManager
    ) external onlyOwner {
        delegationManager = _delegationManager;
        emit DelegationManagerUpdated(delegationManager);
    }

    /**
     * @notice Sets the stakeRegistry contract address
     * @param _stakeRegistry is the stakeRegistry on the eigenlayer contracts
     * @dev only callable by the owner
     */
    function setStakeRegistry(
        address _stakeRegistry
    ) external onlyOwner {
        stakeRegistry = _stakeRegistry;
        emit StakeRegistryUpdated(stakeRegistry);
    }

    /**
     * @notice Sets the avsDirectory contract address
     * @param _avsDirectory is the avsDirectory on the eigenlayer contracts
     * @dev only callable by the owner
     */
    function setAVSDirectory(
        address _avsDirectory
    ) external onlyOwner {
        avsDirectory = _avsDirectory;
        emit AVSDirectoryUpdated(avsDirectory);
    }

    /**
     * @notice Sets threshold stake.
     * @dev Has modifiers: onlyOwner.
     * @param _thresholdStake The threshold stake (uint256).
     */
    function setThresholdStake(
        uint256 _thresholdStake
    ) external onlyOwner {
        thresholdStake = _thresholdStake;
        emit ThresholdStakeUpdated(thresholdStake);
    }

    /**
     * @notice Sets the metadata URI for the AVS
     * @param _metadataURI is the metadata URI for the AVS
     * @dev only callable by the owner
     */
    function setMetadataURI(
        string memory _metadataURI
    ) external onlyOwner {
        IAVSDirectory(avsDirectory).updateAVSMetadataURI(_metadataURI);
    }

    /**
     * @notice Adds permissioned operators to the set for the AVS
     * @param _operators is the address[] to be permissioned for registration on the AVS
     * @dev only callable by the owner
     */
    function addPermissionedOperators(
        address[] calldata _operators
    ) external onlyOwner {
        for (uint256 i = 0; i < _operators.length; i++) {
            permissionedOperators[_operators[i]] = true;
        }
    }

    /**
     * @notice Removes permissioned operators from the set for the AVS
     * @param _operators is the address[] to have permission revoked for registration on the AVS
     * @dev only callable by the owner
     */
    function removePermissionedOperators(
        address[] calldata _operators
    ) external onlyOwner {
        for (uint256 i = 0; i < _operators.length; i++) {
            permissionedOperators[_operators[i]] = false;
        }
    }

    /**
     * @notice Enables the rotation of Predicate Signing Key for an operator
     * @param _oldSigningKey address of the old signing key to remove
     * @param _newSigningKey address of the new signing key to add
     */
    function rotatePredicateSigningKey(address _oldSigningKey, address _newSigningKey) external {
        require(
            operators[msg.sender].status == OperatorStatus.REGISTERED,
            "ServiceManager.rotatePredicateSigningKey: operator is not registered"
        );
        require(
            msg.sender == signingKeyToOperator[_oldSigningKey],
            "ServiceManager.rotatePredicateSigningKey: operator can only change it's own signing key"
        );
        delete signingKeyToOperator[_oldSigningKey];
        signingKeyToOperator[_newSigningKey] = msg.sender;
    }

    /**
     * @notice Registers a new operator
     * @param _operatorSigningKey address of the operator signing key
     * @param _operatorSignature signature used for validation
     */
    function registerOperatorToAVS(
        address _operatorSigningKey,
        SignatureWithSaltAndExpiry memory _operatorSignature
    ) external onlyPermissionedOperator {
        require(
            signingKeyToOperator[_operatorSigningKey] == address(0),
            "ServiceManager.registerOperatorToAVS: operator already registered"
        );
        uint256 totalStake;
        for (uint256 i; i != strategies.length;) {
            totalStake += IDelegationManager(delegationManager).operatorShares(msg.sender, IStrategy(strategies[i]));
            unchecked {
                ++i;
            }
        }

        if (totalStake >= thresholdStake) {
            operators[msg.sender] = OperatorInfo(totalStake, OperatorStatus.REGISTERED);
            signingKeyToOperator[_operatorSigningKey] = msg.sender;
            ISignatureUtils.SignatureWithSaltAndExpiry memory _operatorSig = ISignatureUtils.SignatureWithSaltAndExpiry(
                _operatorSignature.signature, _operatorSignature.salt, _operatorSignature.expiry
            );
            IAVSDirectory(avsDirectory).registerOperatorToAVS(msg.sender, _operatorSig);
            emit OperatorRegistered(msg.sender);
        }
    }

    /**
     * @notice Removes an operator
     * @param _operator the address of the operator to be removed
     */
    function deregisterOperatorFromAVS(
        address _operator
    ) external onlyOwner {
        require(
            operators[_operator].status != OperatorStatus.NEVER_REGISTERED,
            "ServiceManager.deregisterOperatorFromAVS: operator is not registered"
        );
        operators[_operator] = OperatorInfo(0, OperatorStatus.DEREGISTERED);
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(_operator);
        emit OperatorRemoved(_operator);
    }

    /**
     * @notice Deploys a policy for which clients can use
     * @param _policyID is a unique identifier
     * @param _policy is set of formatted rules
     */
    function deployPolicy(
        string memory _policyID,
        string memory _policy,
        uint256 _quorumThreshold
    ) external onlyOwner {
        require(bytes(idToPolicy[_policyID]).length == 0, "ServiceManager.deployPolicy: policy exists");
        idToPolicy[_policyID] = _policy;
        policyIdToThreshold[_policyID] = _quorumThreshold;
        deployedPolicyIDs.push(_policyID);
        emit DeployedPolicy(_policyID, _policy);
    }

    /**
     * @notice Deploys a social graph which clients can use in policy
     * @param _socialGraphID is a unique identifier
     * @param _socialGraphConfig is the config for the social graph
     */
    function deploySocialGraph(string memory _socialGraphID, string memory _socialGraphConfig) external onlyOwner {
        require(
            bytes(idToSocialGraph[_socialGraphID]).length == 0, "ServiceManager.deploySocialGraph: social graph exists"
        );
        idToSocialGraph[_socialGraphID] = _socialGraphConfig;
        socialGraphIDs.push(_socialGraphID);
        emit SocialGraphDeployed(_socialGraphID, _socialGraphConfig);
    }

    /**
     * @notice Gets array of deployed policies
     * @return array of deployed policies
     */
    function getDeployedPolicies() external view returns (string[] memory) {
        return deployedPolicyIDs;
    }

    /**
     * @notice Gets array of social graph IDs
     * @return array of social graph IDs
     */
    function getSocialGraphIDs() external view returns (string[] memory) {
        return socialGraphIDs;
    }

    /**
     * @notice Sets a policy for a client
     * @param _policyID address of the Pod
     */
    function setPolicy(
        string memory _policyID
    ) external {
        clientToPolicy[msg.sender][_policyID] = true;
        emit SetPolicy(msg.sender, _policyID);
    }

    /**
     * @notice Removes a policy for a client
     * @param _policyID address of the Pod
     */
    function removePolicy(
        string memory _policyID
    ) external {
        clientToPolicy[msg.sender][_policyID] = false;
        emit RemovedPolicy(msg.sender, _policyID);
    }

    /**
     * @notice Validates signatures using the OpenZeppelin ECDSA library for the Predicate Single Transaction Model
     * @param _task the params of the task
     * @param  signerAddresses the addresses of the operators
     * @param  signatures the signatures of the operators
     */
    function validateSignatures(
        Task calldata _task,
        address[] memory signerAddresses,
        bytes[] memory signatures
    ) external returns (bool isVerified) {
        require(
            _task.quorumThresholdCount != 0, "ServiceManager.PredicateVerified: quorum threshold count cannot be zero"
        );
        require(signerAddresses.length == signatures.length, "Mismatch between signers and signatures");
        require(block.number <= _task.expireByBlockNumber, "ServiceManager.PredicateVerified: transaction expired");
        require(!spentTaskIds[_task.taskId], "ServiceManager.PredicateVerified: task ID already spent");

        uint256 quorumThreshold = policyIdToThreshold[_task.policyID];
        require(
            quorumThreshold != 0 && _task.quorumThresholdCount == quorumThreshold,
            "ServiceManager.PredicateVerified: deployed policy quorum threshold differs from task quorum threshold"
        );

        bytes32 messageHash = hashTaskWithExpiry(_task);
        for (uint256 i = 0; i < _task.quorumThresholdCount;) {
            if (i > 0 && uint160(signerAddresses[i]) <= uint160(signerAddresses[i - 1])) {
                revert("Signer addresses must be unique and sorted");
            }
            address recoveredSigner = ECDSA.recover(messageHash, signatures[i]);
            require(recoveredSigner == signerAddresses[i], "Invalid signature");
            address operator = signingKeyToOperator[recoveredSigner];
            require(operators[operator].status == OperatorStatus.REGISTERED, "Signer is not a registered operator");
            unchecked {
                ++i;
            }
        }

        emit TaskValidated(
            _task.msgSender,
            _task.target,
            _task.value,
            _task.policyID,
            _task.taskId,
            _task.quorumThresholdCount,
            _task.expireByBlockNumber,
            signerAddresses
        );

        spentTaskIds[_task.taskId] = true;
        return true;
    }

    /**
     * @notice Adds a new strategy
     * @param _strategy address of the strategy to add
     * @param quorumNumber uint8 denoting the quorum number
     * @param index uint256 denoting the index for the strategy
     */
    function addStrategy(address _strategy, uint8 quorumNumber, uint256 index) external onlyOwner {
        IStakeRegistry.StrategyParams memory strategyParams =
            IStakeRegistry(stakeRegistry).strategyParamsByIndex(quorumNumber, index);
        if (address(strategyParams.strategy) != _strategy) {
            revert ServiceManager__InvalidStrategy();
        }
        strategies.push(_strategy);
        emit StrategyAdded(_strategy);
    }

    /**
     * @notice Removes a strategy
     * @param _strategy address of the strategy to be removed
     */
    function removeStrategy(
        address _strategy
    ) external onlyOwner {
        for (uint256 i = 0; i != strategies.length;) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                emit StrategyRemoved(_strategy);
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns the list of strategies that the AVS supports for restaking
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on uniqueness of each element in the returned array.
     *    The off-chain service should do that validation separately
     */
    function getRestakeableStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /**
     * @notice Returns the list of strategies that the operator has potentially restaked on the AVS
     * @param operator The address of the operator to get restaked strategies for
     * @dev This function is intended to be called off-chain
     * @dev No guarantee is made on whether the operator has shares for a strategy in a quorum or uniqueness
     *      of each element in the returned array. The off-chain service should do that validation separately
     */
    function getOperatorRestakedStrategies(
        address operator
    ) external view returns (address[] memory) {
        address[] memory restakedStrategies = new address[](strategies.length);
        uint256 index = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (IDelegationManager(delegationManager).operatorShares(operator, IStrategy(strategies[i])) > 0) {
                restakedStrategies[index] = strategies[i];
                index++;
            }
        }
        return restakedStrategies;
    }

    /**
     * @notice Updates the stakes of all operators for each of the specified quorums in the StakeRegistry. Each quorum also
     * has their quorumUpdateBlockNumber updated. which is meant to keep track of when operators were last all updated at once.
     * @param operatorsPerQuorum is an array of arrays of operators to update for each quorum. Note that each nested array
     * of operators must be sorted in ascending address order to ensure that all operators in the quorum are updated
     * @param quorumNumbers is an array of quorum numbers to update
     * @dev This method is used to update the stakes of all operators in a quorum at once, rather than individually. Performs
     * sanitization checks on the input array lengths, quorumNumbers existing, and that quorumNumbers are ordered. Function must
     * also not be paused by the PAUSED_UPDATE_OPERATOR flag.
     */
    function updateOperatorsForQuorum(address[][] calldata operatorsPerQuorum, bytes calldata quorumNumbers) external {
        if (operatorsPerQuorum.length != quorumNumbers.length) {
            revert ServiceManager__ArrayLengthMismatch();
        }
        address[] memory currQuorumOperators;
        address currOperatorAddress;
        OperatorInfo storage currOperator;
        for (uint256 i; i != quorumNumbers.length;) {
            currQuorumOperators = operatorsPerQuorum[i];
            for (uint256 j; j < currQuorumOperators.length;) {
                currOperatorAddress = currQuorumOperators[j];
                currOperator = operators[currOperatorAddress];
                if (currOperator.status == OperatorStatus.NEVER_REGISTERED) {
                    revert ServiceManager__InvalidOperator();
                }
                uint256 totalStake;
                for (uint256 k; k != strategies.length;) {
                    totalStake += IDelegationManager(delegationManager).operatorShares(
                        currOperatorAddress, IStrategy(strategies[k])
                    );
                    unchecked {
                        ++k;
                    }
                }
                currOperator.totalStake = totalStake;
                currOperator.status =
                    totalStake < thresholdStake ? OperatorStatus.DEREGISTERED : OperatorStatus.REGISTERED;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        emit OperatorsStakesUpdated(operatorsPerQuorum, quorumNumbers);
    }

    /**
     * @notice Performs the hashing of an STM task
     * @param _task parameters of the task
     * @return the keccak256 digest of the task
     */
    function hashTaskWithExpiry(
        Task calldata _task
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _task.taskId,
                _task.msgSender,
                _task.target,
                _task.value,
                _task.encodedSigAndArgs,
                _task.policyID,
                _task.quorumThresholdCount,
                _task.expireByBlockNumber
            )
        );
    }
}
