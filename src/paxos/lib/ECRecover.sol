// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title A library that provides a safe ECDSA recovery function
 * @custom:security-contact smart-contract-security@paxos.com
 */
library ECRecover {
    error InvalidValueS();
    error InvalidSignature();

    /**
     * @dev Recover signer's address from a signed message.
     * Adapted from: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/utils/cryptography/ECDSA.sol
     * Modifications: Accept v, r, and s as separate arguments
     * @param digest    Keccak-256 hash digest of the signed message
     * @param v         v of the signature
     * @param r         r of the signature
     * @param s         s of the signature
     * @return Signer address
     */
    function recover(bytes32 digest, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. https://0xsomeone.medium.com/b002-solidity-ec-signature-pitfalls-b24a0f91aef4 proposes
        // the valid range for s: 0 < s < secp256k1n ÷ 2 + 1, and for v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidValueS();
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();

        return signer;
    }
}
