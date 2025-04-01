// src/types.ts
import type { BigNumber } from "ethers";

export interface PredicateResponse {
    is_compliant: boolean;
    signers: string[];
    signature: string[]; 
    expiry_block: number;
    task_id: string;
}

export interface PredicateRequest {
    to: string;
    from: string;
    data: string;
    msg_value: string;
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
    hookData: string;
}

export interface ExactOutputSingleParams {
    poolKey: PoolKey;
    zeroForOne: boolean;
    amountOut: BigNumber;
    amountInMaximum: BigNumber;
    hookData: string;
}
