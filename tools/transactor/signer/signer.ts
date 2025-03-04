import { ethers } from 'ethers';

interface Signer {
    sign(message: Uint8Array): Promise<string>;
    privateKey(): string;
    publicKey(): string;
    publicKeyBytes(): Uint8Array;
    address(): string;
}

class PrivateKeySigner implements Signer {
    private signingKey: ethers.utils.SigningKey;
    private addressStr: string;

    constructor(privateKey: string) {
        this.signingKey = new ethers.utils.SigningKey(privateKey);
        this.addressStr = ethers.utils.computeAddress(this.signingKey.publicKey);
    }

    static async fromPrivateKey(privateKey: string): Promise<Signer> {
        return new PrivateKeySigner(privateKey);
    }

    static async fromKeystore(path: string, password: string): Promise<Signer> {
        const fs = await import('node:fs/promises');
        const json = await fs.readFile(path, 'utf8');
        const wallet = await ethers.Wallet.fromEncryptedJson(json, password);
        return new PrivateKeySigner(wallet.privateKey);
    }

    async sign(digestHash: Uint8Array): Promise<string> {
        const signature = this.signingKey.signDigest(digestHash);
        return ethers.utils.joinSignature(signature);
    }

    privateKey(): string {
        return this.signingKey.privateKey;
    }

    publicKey(): string {
        return this.signingKey.publicKey;
    }

    publicKeyBytes(): Uint8Array {
        return ethers.utils.arrayify(this.signingKey.publicKey);
    }

    address(): string {
        return this.addressStr;
    }
}

export type { Signer };
export { PrivateKeySigner };