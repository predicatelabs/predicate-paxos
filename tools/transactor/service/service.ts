import { ethers } from 'ethers';
import axios from 'axios';
import type { Config } from '../config/config';
import { encodeBeforeSwap, encodeHookData, waitForReceipt } from './utils';
import type { PoolKey, IPoolManagerSwapParams, PredicateMessage, STMRequest, STMResponse } from '../types/types';
import { ROUTER_ABI } from '../config/abi';

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
        this.swapRouter = new ethers.Contract(config.routerAddress, ROUTER_ABI, this.signer);
        
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
            oneForZero: false,
            amountSpecified: oneEther,
            sqrtPriceLimitX96: ethers.BigNumber.from('4295128740')
        };

        try {
            await this.approveTokensForSwap(oneEther.mul(2)); 
            
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
        } catch (error: unknown) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            throw new Error(`Failed to make predicate request: ${errorMessage}`);
        }
    }

    async getHookData(params: IPoolManagerSwapParams): Promise<string> {
        // Get address first to avoid passing a Promise
        const signerAddress = await this.signer.getAddress();
        
        const data = await encodeBeforeSwap(
            signerAddress,
            {
                Currency0: this.poolKey.currency0,
                Currency1: this.poolKey.currency1,
                Fee: this.poolKey.fee,
                TickSpacing: this.poolKey.tickSpacing,
                Hooks: this.poolKey.hooks
            },
            {
                ZeroForOne: params.zeroForOne,
                AmountSpecified: params.amountSpecified,
                SqrtPriceLimitX96: params.sqrtPriceLimitX96
            }
        );
        
        const stmRequest: STMRequest = {
            to: this.poolKey.hooks,
            from: signerAddress,
            data: ethers.utils.hexlify(data),
            value: '0'
        };

        console.log('STM Request:', stmRequest);
        const stmResponse = await this.makePredicateRequest(stmRequest);

        if (!stmResponse.isCompliant) {
            throw new Error('STM response is not compliant');
        }

        console.log('STM Response:', stmResponse);
        const pm = {
            TaskId: stmResponse.taskId,
            ExpireByBlockNumber: ethers.BigNumber.from(stmResponse.expiryBlock),
            SignerAddresses: stmResponse.signers.map(addr => ethers.utils.getAddress(addr)),
            Signatures: stmResponse.signatures
        };

        return encodeHookData(pm, signerAddress, ethers.BigNumber.from(0));
    }

    async approveTokensForSwap(amount: ethers.BigNumber): Promise<void> {
        const token0 = new ethers.Contract(
            this.poolKey.currency0,
            ["function approve(address spender, uint256 amount) external returns (bool)"],
            this.signer
        );
        
        const token1 = new ethers.Contract(
            this.poolKey.currency1,
            ["function approve(address spender, uint256 amount) external returns (bool)"],
            this.signer
        );
        
        console.log("Approving tokens for swap...");
        
        await (await token0.approve(this.swapRouter.address, amount)).wait();
        await (await token1.approve(this.swapRouter.address, amount)).wait();
        
        console.log("Token approvals complete");
    }
}

export function createContext() {
    return {};
}

export async function runService(_ctx: unknown, config: Config) {
    const service = new TransactorService(config);
    await service.start();
}
