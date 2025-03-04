import { ethers } from 'ethers';
import axios from 'axios';
import type { } from '../config/config';
import { encodeBeforeSwap, encodeHookData, waitForReceipt } from './utils';
import type { PoolKey, IPoolManagerSwapParams, PredicateMessage, STMRequest, STMResponse } from '../types/types';

const API_REQUEST_TIMEOUT = 5000; // 5 seconds

export class TransactorService {
    private provider: ethers.providers.JsonRpcProvider;
    private signer: ethers.Signer;
    private swapRouter: ethers.Contract;
    private config: Config;
    private poolKey: PoolKey;

    constructor(config: Config) {
        this.config = config;
        this.provider = new ethers.providers.JsonRpcProvider(config.ethRpcUrl);
        this.signer = new ethers.Wallet(config.privateKey, this.provider);
        this.swapRouter = new ethers.Contract(config.routerAddress, [], this.signer);
        
        this.poolKey = {
            currency0: config.currency0Address,
            currency1: config.currency1Address,
            fee: config.lpFees,
            tickSpacing: config.tickSpacing,
            hooks: config.hookAddress
        };
    }

    async start() {
        console.log(`Running transactor service in ${this.config.environment} environment`);

        const oneEther = ethers.utils.parseEther('1');
        const params: IPoolManagerSwapParams = {
            zeroForOne: true,
            amountSpecified: oneEther,
            sqrtPriceLimitX96: ethers.BigNumber.from('4295128740')
        };

        try {
            const hookData = await this.getHookData(params);
            console.log('Hook Data:', hookData);

            const tx = await this.swapRouter.swap(this.poolKey, params, hookData);
            const receipt = await tx.wait();

            if (receipt.status !== 1) {
                throw new Error(`Transaction failed: ${receipt.transactionHash}`);
            }
            console.log(`Transaction successful: ${receipt.transactionHash}`);
        } catch (error) {
            console.error('Transaction failed:', error);
        }
    }

    async makePredicateRequest(requestData: STMRequest): Promise<STMResponse> {
        console.log(`Making STM request in ${this.config.environment} environment`);
        try {
            const response = await axios.post<STMResponse>(this.config.predicateApiUrl, requestData, {
                headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': this.config.apiKey
                },
                timeout: API_REQUEST_TIMEOUT
            });
            return response.data;
        } catch (error) {
            throw new Error(`Failed to make predicate request: ${error.message}`);
        }
    }

    async getHookData(params: IPoolManagerSwapParams): Promise<string> {
        const data = encodeBeforeSwap(this.signer, this.poolKey, params);
        
        const stmRequest: STMRequest = {
            to: this.poolKey.hooks,
            from: await this.signer.getAddress(),
            data: ethers.utils.hexlify(data),
            value: '0'
        };

        console.log('STM Request:', stmRequest);
        const stmResponse = await this.makePredicateRequest(stmRequest);

        if (!stmResponse.isCompliant) {
            throw new Error('STM response is not compliant');
        }

        console.log('STM Response:', stmResponse);
        const pm: PredicateMessage = {
            taskId: stmResponse.taskId,
            expireByBlockNumber: ethers.BigNumber.from(stmResponse.expiryBlock),
            signerAddresses: stmResponse.signers.map(addr => ethers.utils.getAddress(addr)),
            signatures: stmResponse.signatures.map(sig => ethers.utils.arrayify(sig))
        };

        return encodeHookData(pm, await this.signer.getAddress(), ethers.BigNumber.from(0));
    }
}

export function createContext() {
    return {};
}

export async function runService(_ctx: any, config: Config) {
    const service = new TransactorService(config);
    await service.start();
}
