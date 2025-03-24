// src/types.ts
import { BigNumber } from "ethers";

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

// Additional types used in service.ts:
export interface PoolKey {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
}

export interface SwapParams {
    zeroForOne: boolean;
    amountSpecified: BigNumber;
    sqrtPriceLimitX96: BigNumber;
}
