// src/service.ts
import { ethers, BigNumber } from "ethers";
import fetch from "node-fetch"; // If using Node.js <18; otherwise, use the global fetch
import { Config } from "./config";
import { SwapRouterABI } from "./swapRouter";
import {
    STMRequest,
    STMResponse,
    PredicateMessage,
    PoolKey,
    SwapParams,
} from "./types";

export class TransactorService {
    environment: string;
    predicateAPIURL: string;
    apiKey: string;
    swapRouter: ethers.Contract;
    routerAddress: string;
    poolKey: PoolKey;
    provider: ethers.providers.Provider;
    wallet: ethers.Wallet;

    constructor(private config: Config) {
        this.environment = config.environment;
        this.predicateAPIURL = config.predicateAPIURL;
        this.apiKey = config.apiKey;
        // Create provider and wallet
        this.provider = new ethers.providers.JsonRpcProvider(config.ethRPCURL);
        this.wallet = new ethers.Wallet(config.privateKey, this.provider);
        this.routerAddress = config.routerAddress;
        this.swapRouter = new ethers.Contract(
            this.routerAddress,
            SwapRouterABI,
            this.wallet,
        );

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
        const oneEther = ethers.BigNumber.from("1000000000000000000");
        const params: SwapParams = {
            zeroForOne: true,
            amountSpecified: oneEther,
            sqrtPriceLimitX96: BigNumber.from("4295128740"),
        };

        const hookData = await this.getHookData(params);
        console.log("Hook Data:", hookData);

        const tx = await this.swapRouter.swap(this.poolKey, params, hookData);
        console.log("Transaction submitted, hash:", tx.hash);
        const receipt = await tx.wait();
        if (receipt.status !== 1) {
            throw new Error("Transaction failed");
        }
        console.log("Transaction successful:", receipt.transactionHash);
    }

    async getHookData(params: SwapParams): Promise<string> {
        const dataBeforeSwap = this.encodeBeforeSwap(
            this.wallet.address,
            this.poolKey,
            params,
        );

        const stmRequest: STMRequest = {
            to: this.config.predicateHookAddress,
            from: this.wallet.address,
            data: dataBeforeSwap,
            msg_value: "0",
        };
        console.log("STM Request:", stmRequest);

        const response = await fetch(this.predicateAPIURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": this.apiKey,
            },
            body: JSON.stringify(stmRequest),
        });

        const responseText = await response.text();
        if (!response.ok) {
            throw new Error(
                `Failed to fetch hook data: ${response.status} ${response.statusText}\nResponse: ${responseText}`,
            );
        }

        let stmResponse: STMResponse;
        try {
            stmResponse = JSON.parse(responseText) as STMResponse;
        } catch (error) {
            throw new Error(
                `Failed to parse API response as JSON: ${error}\nResponse: ${responseText}`,
            );
        }

        if (!stmResponse.is_compliant) {
            throw new Error("STM Response is not compliant");
        }
        console.log("STM Response:", stmResponse);

        const pm: PredicateMessage = {
            taskId: stmResponse.task_id,
            expireByBlockNumber: BigNumber.from(stmResponse.expiry_block),
            signerAddresses: stmResponse.signers,
            signatures: stmResponse.signature,
        };

        const hookDataEncoded = this.encodeHookData(pm);
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
    ): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            ["tuple(string,uint256,address[],bytes[])"],
            [
                [
                    pm.taskId,
                    pm.expireByBlockNumber.toString(),
                    pm.signerAddresses,
                    pm.signatures,
                ]
            ],
        );
        return encoded;
    }
}
