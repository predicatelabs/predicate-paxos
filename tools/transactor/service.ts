import { ethers, BigNumber } from "ethers";
import type { Config } from "./config";
import { SwapRouterABI } from "./swapRouter";
import type {
    PredicateRequest,
    PredicateMessage,
    PoolKey,
    SwapParams,
} from "./types";
import * as sdk from '@predicate/predicate-sdk'


const SQRT_PRICE_LIMIT_X96 = BigNumber.from("4295128740");

export class TransactorService {
    environment: string;
    predicateAPIURL: string;
    apiKey: string;
    swapRouter: ethers.Contract;
    routerAddress: string;
    poolKey: PoolKey;
    provider: ethers.providers.Provider;
    wallet: ethers.Wallet;
    predicateClient: sdk.PredicateClient;

    constructor(private config: Config) {
        this.environment = config.environment;
        this.predicateAPIURL = config.predicateAPIURL;
        this.apiKey = config.apiKey;
        this.provider = new ethers.providers.JsonRpcProvider(config.ethRPCURL);
        this.wallet = new ethers.Wallet(config.privateKey, this.provider);
        this.routerAddress = config.routerAddress;
        this.swapRouter = new ethers.Contract(
            this.routerAddress,
            SwapRouterABI,
            this.wallet,
        );

        this.predicateClient = new sdk.PredicateClient({
            apiUrl: this.predicateAPIURL,
            apiKey: this.apiKey,
        });

        this.poolKey = {
            currency0: config.currency0Address,
            currency1: config.currency1Address,
            fee: config.lpFees,
            tickSpacing: config.tickSpacing,
            hooks: config.autoWrapperAddress,
        };

        console.log("Config values:", {
            routerAddress: config.routerAddress,
            currency0Address: config.currency0Address,
            currency1Address: config.currency1Address,
            predicateHookAddress: config.predicateHookAddress,
            autoWrapperAddress: config.autoWrapperAddress,
            ethRPCURL: config.ethRPCURL,
        });
    }

    async start() {
        console.log(
            `Running transactor service in ${this.environment} environment`,
        );
        const amount = this.config.amount 
            ? ethers.BigNumber.from(this.config.amount) 
            : ethers.BigNumber.from("1000000000000000000"); 

        const params: SwapParams = {
            zeroForOne: true,
            amountSpecified: amount,
            sqrtPriceLimitX96: SQRT_PRICE_LIMIT_X96,
        };

        const hookData = await this.getAutoWrapperHookData(params);
        console.log("Hook Data:", hookData);

        const tx = await this.swapRouter.swap(this.poolKey, params, hookData);
        console.log("Transaction submitted, hash:", tx.hash);
        const receipt = await tx.wait();
        if (receipt.status !== 1) {
            throw new Error("Transaction failed");
        }
        console.log("Transaction successful:", receipt.transactionHash);
    }

    async getAutoWrapperHookData(params: SwapParams): Promise<string> {
        const dataBeforeSwap = this.encodeBeforeSwap(
            this.wallet.address,
            this.poolKey,
            params,
        );

        const predicateRequest: PredicateRequest = {
            to: this.config.predicateHookAddress,
            from: this.wallet.address,
            data: dataBeforeSwap,
            msg_value: "0",
        };
        console.log("Predicate Request:", predicateRequest);

        const predicateResponse = await this.predicateClient.verify(predicateRequest);
        
        if (!predicateResponse.is_compliant) {
            throw new Error("Predicate Response is not compliant");
        }
        console.log("Predicate Response:", predicateResponse);

        const pm: PredicateMessage = {
            taskId: predicateResponse.task_id,
            expireByBlockNumber: BigNumber.from(predicateResponse.expiry_block),
            signerAddresses: predicateResponse.signers,
            signatures: predicateResponse.signature,
        };

        const hookDataEncoded = this.encodeHookData(
            pm,
            this.wallet.address,
            BigNumber.from("0"),
        );
        return hookDataEncoded;
    }

    encodeBeforeSwap(sender: string, key: PoolKey, params: SwapParams): string {
        const functionSignature =
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)";
        const selector = ethers.utils
            .keccak256(ethers.utils.toUtf8Bytes(functionSignature))
            .substring(0, 10);
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encodedArgs = abiCoder.encode(
            [
                "address",
                "address",
                "address",
                "uint24",
                "int24",
                "address",
                "bool",
                "int256",
                "uint160",
            ],
            [
                sender,
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                key.hooks,
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
            ],
        );
        return selector + encodedArgs.substring(2);
    }

    encodeHookData(
        pm: PredicateMessage,
        msgSender: string,
        msgValue: BigNumber,
    ): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            ["tuple(string,uint256,address[],bytes[])", "address", "uint256"],
            [
                [
                    pm.taskId,
                    pm.expireByBlockNumber.toString(),
                    pm.signerAddresses,
                    pm.signatures,
                ],
                msgSender,
                msgValue.toString(),
            ],
        );
        return encoded;
    }
}
