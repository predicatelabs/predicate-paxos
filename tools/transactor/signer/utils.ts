import { ethers } from 'ethers';
import fs from 'node:fs';

async function getECDSAPrivateKey(keyStoreFile: string, password: string): Promise<ethers.Wallet> {
    const keyStoreContents = await fs.promises.readFile(keyStoreFile, 'utf8');
    const wallet = await ethers.Wallet.fromEncryptedJson(keyStoreContents, password);
    return wallet;
}

function publicKeyToBytes(publicKey: string): Uint8Array {
    return ethers.utils.arrayify(publicKey);
}

function verifySignature(digestHash: Uint8Array, signature: string, publicKeyBytes: Uint8Array): boolean {
    const recoveredAddress = ethers.utils.recoverAddress(digestHash, signature);
    const publicKeyAddress = ethers.utils.computeAddress(publicKeyBytes);
    return recoveredAddress === publicKeyAddress;
}

export { getECDSAPrivateKey, publicKeyToBytes, verifySignature };