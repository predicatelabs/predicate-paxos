// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import {Task} from "../../../src/interfaces/IPredicateManager.sol";

library TestUtils {
    function bytes32ToString(
        bytes32 _bytes32
    ) public pure returns (string memory) {
        uint8 i = 0;
        bytes memory bytesArray = new bytes((_bytes32.length * 2));
        for (i = 0; i < bytesArray.length - 1; i++) {
            uint8 _f = uint8(_bytes32[i / 2] & 0x0f);
            uint8 _l = uint8(_bytes32[i / 2] >> 4);

            bytesArray[i] = toByte(_l);
            i = i + 1;
            bytesArray[i] = toByte(_f);
        }

        return string(bytesArray);
    }

    function toByte(
        uint8 _uint8
    ) public pure returns (bytes1) {
        if (_uint8 < 10) {
            return bytes1(_uint8 + 48);
        } else {
            return bytes1(_uint8 + 87);
        }
    }

    function hashTaskSTM(
        Task memory task
    ) public pure returns (bytes32 _messageHash) {
        _messageHash = keccak256(
            abi.encode(
                task.taskId,
                task.msgSender,
                task.target,
                task.value,
                task.encodedSigAndArgs,
                task.policyID,
                task.quorumThresholdCount,
                task.expireByBlockNumber
            )
        );
    }
}
