// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.12;

import {Ownable} from "openzeppelin/access/Ownable.sol";

import {PredicateClient} from "../mixins/PredicateClient.sol";
import {PredicateMessage} from "../interfaces/IPredicateClient.sol";
import {IPredicateManager} from "../interfaces/IPredicateManager.sol";

// This is just a simple example of a coin-like contract.
// It is not ERC20 compatible and cannot be expected to talk to other
// coin/token contracts.

contract MetaCoin is PredicateClient, Ownable {
    mapping(address => uint256) public balances;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    constructor(address _owner, address _serviceManager, string memory _policyID) {
        balances[_owner] = 10_000_000_000_000;
        _initPredicateClient(_serviceManager, _policyID);
        _transferOwnership(_owner);
    }

    function sendCoin(address receiver, uint256 amount, PredicateMessage calldata predicateMessage) public payable {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_sendCoin(address,uint256)", receiver, amount);
        require(
            _authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, msg.value),
            "MetaCoin: unauthorized transaction"
        );

        // business logic function that is protected
        _sendCoin(receiver, amount);
    }

    // @inheritdoc IPredicateClient
    function setPolicy(
        string memory _policyID
    ) external onlyOwner {
        _setPolicy(_policyID);
    }

    // @inheritdoc IPredicateClient
    function setPredicateManager(
        address _predicateManager
    ) public onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    // business logic function that is protected
    function _sendCoin(address receiver, uint256 amount) internal {
        require(balances[msg.sender] >= amount, "MetaCoin: insufficient balance");
        balances[msg.sender] -= amount;
        balances[receiver] += amount;
        emit Transfer(msg.sender, receiver, amount);
    }

    function getBalance(
        address addr
    ) public view returns (uint256) {
        return balances[addr];
    }
}
