import type { ethers } from 'ethers';
import type { PoolKey, IPoolManagerSwapParams, PredicateMessage } from '../types/types';

export function encodeBeforeSwap(signer: ethers.Signer, poolKey: PoolKey, params: IPoolManagerSwapParams): string {
    return "0x";
}

export function encodeHookData(pm: PredicateMessage, sender: string, value: ethers.BigNumber): string {
    return "0x";
}

export async function waitForReceipt(tx: ethers.providers.TransactionResponse): Promise<ethers.providers.TransactionReceipt> {
    return await tx.wait();
} 