import type { BigNumber, ethers } from 'ethers';

export interface STMResponse {
    isCompliant: boolean;
    signers: string[];
    signatures: string[];
    expiryBlock: number;
    taskId: string;
}

export interface STMRequest {
    to: string;
    from: string;
    data: string;
    value: string; 
}

export interface PoolKey {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
}

export interface IPoolManagerSwapParams {
    zeroForOne: boolean;
    amountSpecified: ethers.BigNumber;
    sqrtPriceLimitX96: ethers.BigNumber;
}

export interface PredicateMessage {
    taskId: string;
    expireByBlockNumber: ethers.BigNumber;
    signerAddresses: string[];
    signatures: Uint8Array[];
}

