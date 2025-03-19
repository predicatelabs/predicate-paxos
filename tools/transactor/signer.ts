// src/signer.ts
import { Wallet } from "ethers";

export interface Signer {
  sign(message: Uint8Array): Promise<string>;
  getPrivateKey(): string;
  getPublicKey(): string;
  getAddress(): string;
}

export class PrivateKeySigner implements Signer {
  wallet: Wallet;

  constructor(privateKey: string) {
    this.wallet = new Wallet(privateKey);
  }

  async sign(message: Uint8Array): Promise<string> {
    // wallet.signMessage automatically prefixes the message per EIP-191.
    return await this.wallet.signMessage(message);
  }

  getPrivateKey(): string {
    return this.wallet.privateKey;
  }

  getPublicKey(): string {
    return this.wallet.publicKey;
  }

  getAddress(): string {
    return this.wallet.address;
  }
}
