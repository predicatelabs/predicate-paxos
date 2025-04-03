// src/types.ts
import type { BigNumber } from "ethers";

export interface PredicateResponse {
    isCompliant: boolean;
    signers: string[];
    signature: string[]; 
    expiryBlock: number;
    taskId: string;
}

export interface PredicateRequest {
    to: string;
    from: string;
    data: string;
    msgValue: string;
}

export interface PredicateMessage {
    taskId: string;
    expireByBlockNumber: BigNumber;
    signerAddresses: string[];
    signatures: string[];
}

export interface PoolKey {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
}

export interface ExactInputSingleParams {
    poolKey: PoolKey;
    zeroForOne: boolean;
    amountIn: BigNumber;
    amountOutMinimum: BigNumber;
    hookData: string | Uint8Array;
}

export interface ExactOutputSingleParams {
    poolKey: PoolKey;
    zeroForOne: boolean;
    amountOut: BigNumber;
    amountInMaximum: BigNumber;
    hookData: string | Uint8Array;
}
