// src/service.ts
import { ethers, BigNumber } from "ethers";
import fetch from "node-fetch"; // If using Node.js <18; otherwise, use the global fetch
import { Config } from "./config";
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

        // Create a contract instance for the swap router.
        // NOTE: Replace the ABI below with your actual contract ABI.
        const swapRouterAbi = [
            // Example function definition for Swap; adjust types as needed.
            "function Swap((address,address,address,uint24,int24,address) poolKey, (bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) params, bytes hookData) external returns (bytes32)",
        ];
        this.routerAddress = config.routerAddress;
        this.swapRouter = new ethers.Contract(
            this.routerAddress,
            swapRouterAbi,
            this.wallet,
        );

        // Construct poolKey
        this.poolKey = {
            currency0: config.currency0Address,
            currency1: config.currency1Address,
            fee: config.lpFees,
            tickSpacing: config.tickSpacing,
            hooks: config.hookAddress,
        };
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

        // Get hook data from predicate API
        const hookData = await this.getHookData(params);
        console.log("Hook Data:", hookData);

        // Call the Swap function on the router contract
        const tx = await this.swapRouter.Swap(this.poolKey, params, hookData);
        console.log("Transaction submitted, hash:", tx.hash);
        const receipt = await tx.wait();
        if (receipt.status !== 1) {
            throw new Error("Transaction failed");
        }
        console.log("Transaction successful:", receipt.transactionHash);
    }

    async getHookData(params: SwapParams): Promise<string> {
        // Encode the swap parameters (similar to encodeBeforeSwap in Go)
        const dataBeforeSwap = this.encodeBeforeSwap(
            this.wallet.address,
            this.poolKey,
            params,
        );

        // Build the STMRequest object
        const stmRequest: STMRequest = {
            to: this.poolKey.hooks,
            from: this.wallet.address,
            data: dataBeforeSwap,
            msg_value: "0",
        };
        console.log("STM Request:", stmRequest);

        // Make the HTTP POST request to the predicate API
        const response = await fetch(this.predicateAPIURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": this.apiKey,
            },
            body: JSON.stringify(stmRequest),
        });
        
        // Log the raw response for debugging
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

        // Build the PredicateMessage object
        const pm: PredicateMessage = {
            taskId: stmResponse.task_id,
            expireByBlockNumber: BigNumber.from(stmResponse.expiry_block),
            signerAddresses: stmResponse.signers,
            signatures: stmResponse.signature,
        };

        // Encode the PredicateMessage and additional parameters (similar to encodeHookData in Go)
        const hookDataEncoded = this.encodeHookData(
            pm,
            this.wallet.address,
            BigNumber.from("0"),
        );
        return hookDataEncoded;
    }

    encodeBeforeSwap(sender: string, key: PoolKey, params: SwapParams): string {
        // The Go version computed the 4-byte selector for:
        // _beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)
        // Here we do the same manually.
        const functionSignature =
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)";
        const selector = ethers.utils
            .keccak256(ethers.utils.toUtf8Bytes(functionSignature))
            .substring(0, 10);
        // Pack the arguments with the appropriate types.
        // (Note: ethers does not natively support "uint24" or "int24", so we assume fee and tickSpacing fit in a normal number.)
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
        // Return the concatenation of the selector and encoded arguments (removing the "0x" prefix from the args)
        return selector + encodedArgs.substring(2);
    }

    encodeHookData(
        pm: PredicateMessage,
        msgSender: string,
        msgValue: BigNumber,
    ): string {
        // Encode (PredicateMessage, address, uint256)
        // PredicateMessage is defined as a tuple: (string, uint256, address[], bytes[])
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
