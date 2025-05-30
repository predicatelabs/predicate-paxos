import { ethers, BigNumber } from "ethers";
import type { Config } from "./config";
import { SwapRouterABI } from "./swapRouter";
import type {
    PredicateRequest,
    PredicateMessage,
    PoolKey,
    ExactInputSingleParams,
    ExactOutputSingleParams,
    PredicateResponse,
} from "./types";

const SWAP_EXACT_IN_SINGLE_ACTION = 0x06;
const SWAP_EXACT_OUT_SINGLE_ACTION = 0x08;
const TAKE_ALL_ACTION = 0x0f;
const SETTLE_ALL_ACTION = 0x0c;
const SETTLE_ACTION = 0x0b;

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

        const zeroForOne = true;
        const amountInMaximum = ethers.utils.parseEther("10"); // 1e18
        const amountOut = BigNumber.from("1000000");
        const hookData = await this.getAutoWrapperHookData(false, amountOut);
        console.log("Hook Data:", hookData);

        // // Exact input USDC -> WUSDL swap on WUSDL/USDC pool
        // const params: ExactInputSingleParams = {
        //     poolKey: this.poolKey,
        //     zeroForOne: zeroForOne,
        //     amountIn: amountIn,
        //     amountOutMinimum: BigNumber.from("100000"),
        //     hookData: hookData,
        // };
        // const actions = [SWAP_EXACT_IN_SINGLE_ACTION, SETTLE_ALL_ACTION, TAKE_ALL_ACTION];
        // const encodedSwap = this.encodeSwapExactInputSingle(actions, params);
        // console.log("Encoded Swap:", encodedSwap);


        // Exact output WUSDL -> USDC swap on WUSDL/USDC pool
        const params: ExactOutputSingleParams = {
            poolKey: this.poolKey,
            zeroForOne: zeroForOne,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            hookData: hookData,
        };
        const actions = [SWAP_EXACT_OUT_SINGLE_ACTION, TAKE_ALL_ACTION, SETTLE_ALL_ACTION];
        const encodedSwap = this.encodeSwapExactOutputSingle(actions, params);
        console.log("Encoded Swap:", encodedSwap);


        const tx = await this.swapRouter.execute(encodedSwap, {
            gasLimit: 1000000,
        });
        console.log("Transaction submitted, hash:", tx.hash);
        const receipt = await tx.wait();
        if (receipt.status !== 1) {
            throw new Error("Transaction failed");
        }
        console.log("Transaction successful:", receipt.transactionHash);
    }

    async getAutoWrapperHookData(zeroForOne: boolean, amountSpecified: BigNumber): Promise<string> {
        const dataBeforeSwap = this.encodeBeforeSwap(
            this.wallet.address,
            this.poolKey,
            zeroForOne,
            amountSpecified,
        );

        const predicateRequest: PredicateRequest = {
            to: this.config.predicateHookAddress,
            from: this.wallet.address,
            data: dataBeforeSwap,
            msg_value: "0",
        };
        console.log("Predicate Request:", predicateRequest);

        const response = await fetch(this.predicateAPIURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": this.apiKey,
            },
            body: JSON.stringify(predicateRequest),
        });

        const responseText = await response.text();
        if (!response.ok) {
            throw new Error(
                `Failed to fetch hook data: ${response.status} ${response.statusText}\nResponse: ${responseText}`,
            );
        }

        var predicateResponse: PredicateResponse;
        try {
            predicateResponse = JSON.parse(responseText) as PredicateResponse;
        } catch (error) {
            throw new Error(
                `Failed to parse API response as JSON: ${error}\nResponse: ${responseText}`,
            );
        }

        console.log("Predicate Response:", predicateResponse);
        
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
        console.log("Predicate Message:", pm);

        return this.encodeHookData(pm);
    }

    encodeBeforeSwap(sender: string, key: PoolKey, zeroForOne: boolean, amountSpecified: BigNumber): string {
        const functionSignature =
            "_beforeSwap(address,address,address,uint24,int24,address,bool,int256)";
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
            ],
            [
                sender,
                key.currency0,
                key.currency1,
                key.fee,
                key.tickSpacing,
                key.hooks,
                zeroForOne,
                amountSpecified,
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
                ],
            ],
        );
        return encoded;
    }

    encodeSwapExactInputSingle(actions: number[], params: ExactInputSingleParams): string {
        var paramsArray = new Array<string>();
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encodedParams = this.encodeExactInputSingleParams(params);
        paramsArray.push(encodedParams);
        paramsArray.push(this.encodeSettleAll(params.poolKey.currency0, params.amountIn));
        paramsArray.push(this.encodeTakeAll(params.poolKey.currency1, params.amountOutMinimum));
        
        // Encode actions using abi.encodePacked equivalent
        const encodedActions = ethers.utils.solidityPack(
            ["uint8", "uint8", "uint8"],
            [actions[0], actions[1], actions[2]]
        );
        
        const encoded = abiCoder.encode(
            ["bytes", "bytes[]"],
            [encodedActions, paramsArray],
        );
        return encoded;
    }

    encodeSwapExactOutputSingle(actions: number[], params: ExactOutputSingleParams): string {
        var paramsArray = new Array<string>();
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encodedParams = this.encodeExactOutputSingleParams(params);
        paramsArray.push(encodedParams);
        paramsArray.push(this.encodeTakeAll(params.poolKey.currency1, params.amountOut));
        paramsArray.push(this.encodeSettleAll(params.poolKey.currency0, params.amountInMaximum));
        
        // Encode actions using abi.encodePacked equivalent
        const encodedActions = ethers.utils.solidityPack(
            ["uint8", "uint8", "uint8"],
            [actions[0], actions[1], actions[2]]
        );
        
        const encoded = abiCoder.encode(
            ["bytes", "bytes[]"],
            [encodedActions, paramsArray],
        );
        return encoded;
    }

    encodeExactInputSingleParams(params: ExactInputSingleParams): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        
        const encoded = abiCoder.encode(
            [
                "tuple(tuple(address,address,uint24,int24,address),bool,uint128,uint128,bytes)"
            ],
            [
                [   
                    [
                        params.poolKey.currency0,
                        params.poolKey.currency1,
                        params.poolKey.fee,
                        params.poolKey.tickSpacing,
                        params.poolKey.hooks
                    ],
                    params.zeroForOne,
                    params.amountIn,
                    params.amountOutMinimum,
                    params.hookData
                ]
            ]
        );
        return encoded;
    }

    encodeExactOutputSingleParams(params: ExactOutputSingleParams): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            [
                "tuple(tuple(address,address,uint24,int24,address),bool,uint128,uint128,bytes)"
            ],
            [
                [   
                    [
                        params.poolKey.currency0,
                        params.poolKey.currency1,
                        params.poolKey.fee,
                        params.poolKey.tickSpacing,
                        params.poolKey.hooks
                    ],
                    params.zeroForOne,
                    params.amountOut,
                    params.amountInMaximum,
                    params.hookData
                ]
            ]
        );
        return encoded;
    }
    encodeSettle(currency: string, amount: BigNumber, isPayer: boolean): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            ["address", "uint256", "bool"],
            [currency, amount, isPayer],
        );
        return encoded;
    }

    encodeTakeAll(currency: string, amount: BigNumber): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            ["address", "uint256"],
            [currency, amount],
        );
        return encoded;
    }

    encodeSettleAll(currency: string, amount: BigNumber): string {
        const abiCoder = ethers.utils.defaultAbiCoder;
        const encoded = abiCoder.encode(
            ["address", "uint256"],
            [currency, amount],
        );
        return encoded;
    }
}