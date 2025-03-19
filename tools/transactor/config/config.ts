import { ethers } from 'ethers';
import { AbiCoder, keccak256 } from 'ethers/lib/utils';
import type { PredicateMessage, PoolKey, IPoolManagerSwapParams } from '../types/types';

export function encodeBeforeSwap(
    sender: string,
    key: PoolKey,
    params: IPoolManagerSwapParams
): string {
    const abiCoder = new AbiCoder();
    const methodSig = '_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)';
    const selector = keccak256(Buffer.from(methodSig)).slice(0, 10);
    
    const encodedArgs = abiCoder.encode(
        [
            'address', 'address', 'address', 'uint24', 'int24', 'address', 'bool', 'int256', 'uint160'
        ],
        [
            sender, key.currency0, key.currency1,
            key.fee, key.tickSpacing, key.hooks,
            params.zeroForOne, params.amountSpecified, params.sqrtPriceLimitX96
        ]
    );
    
    return selector + encodedArgs.slice(2);
}

export function encodeHookData(
    pm: PredicateMessage,
    msgSender: string,
    msgValue: ethers.BigNumber
): string {
    const abiCoder = new AbiCoder();
    const encoded = abiCoder.encode(
        [
            'tuple(string,uint256,address[],bytes[])', 'address', 'uint256'
        ],
        [
            [pm.taskId, pm.expireByBlockNumber, pm.signerAddresses, pm.signatures],
            msgSender,
            msgValue
        ]
    );
    return encoded;
}

export async function getChainID(provider: ethers.providers.JsonRpcProvider): Promise<ethers.BigNumber> {
    return await provider.getNetwork().then(network => ethers.BigNumber.from(network.chainId));
}

export function getECDSAKey(privateKeyStr: string): ethers.Wallet {
    return new ethers.Wallet(privateKeyStr);
}

export async function waitForReceipt(
    provider: ethers.providers.JsonRpcProvider,
    txHash: string
): Promise<ethers.providers.TransactionReceipt | null> {
    while (true) {
        const receipt = await provider.getTransactionReceipt(txHash);
        if (receipt) {
            return receipt;
        }
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
}

// Define the Config interface for the transactor service
export interface Config {
    predicateApiUrl: string;
    apiKey: string;
    ethRpcUrl: string;
    privateKey: string;
    environment: string;
    currency0Address: string;
    currency1Address: string;
    routerAddress: string;
    hookAddress: string;
    lpFees: number;
    tickSpacing: number;
}
