// src/main.ts
import { Command } from "commander";
import { TransactorService } from "./service";
import { validateConfig, Config } from "./config";

const program = new Command();

let config: Config = {
    predicateAPIURL: "http://0.0.0.0:80/task",
    apiKey: "",
    ethRPCURL: "http://localhost:8545",
    privateKey:
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    environment: "local",
    currency0Address: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
    currency1Address: "0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1",
    routerAddress: "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318",
    predicateHookAddress: "0x86Dfe3508346255a9540200f231F7248d3d8c880",
    autoWrapperAddress: "0x3fDf5a1EAaF5d31C8aAb68ffB9b694B546FE6888",
    lpFees: 0,
    tickSpacing: 60,
};

program
    .option(
        "--predicate-api-url <url>",
        "Predicate API URL",
        config.predicateAPIURL,
    )
    .option("--api-key <key>", "API key", config.apiKey)
    .option("--eth-rpc-url <url>", "Ethereum RPC URL", config.ethRPCURL)
    .option("--private-key <key>", "Private key", config.privateKey)
    .option("--environment <env>", "Environment", config.environment)
    .option(
        "--currency0-address <address>",
        "Currency0 address",
        config.currency0Address,
    )
    .option(
        "--currency1-address <address>",
        "Currency1 address",
        config.currency1Address,
    )
    .option(
        "--swap-router-address <address>",
        "Swap router address",
        config.routerAddress,
    )
    .option(
        "--predicate-hook-address <address>",
        "Predicate hook address",
        config.predicateHookAddress,
    )
    .option(
        "--auto-wrapper-address <address>",
        "Auto wrapper address",
        config.autoWrapperAddress,
    )
    .option(
        "--lp-fees <number>",
        "LP fees",
        (val) => parseInt(val),
        config.lpFees,
    )
    .option(
        "--tick-spacing <number>",
        "Tick spacing",
        (val) => parseInt(val),
        config.tickSpacing,
    );

program.parse(process.argv);
const options = program.opts();

// Override default config with command-line options where provided
config = {
    ...config,
    predicateAPIURL: options.predicateApiUrl || options.predicate_api_url,
    apiKey: options.apiKey,
    ethRPCURL: options.ethRpcUrl || options.eth_rpc_url,
    privateKey: options.privateKey,
    environment: options.environment,
    currency0Address: options.currency0Address,
    currency1Address: options.currency1Address,
    routerAddress: options.swapRouterAddress || options.swap_router_address,
    predicateHookAddress: options.predicateHookAddress,
    autoWrapperAddress: options.autoWrapperAddress,
    lpFees: options.lpFees,
    tickSpacing: options.tickSpacing,
};

try {
    validateConfig(config);
} catch (err: any) {
    console.error("Configuration error:", err.message);
    process.exit(1);
}

(async () => {
    const service = new TransactorService(config);
    try {
        await service.start();
    } catch (err) {
        console.error("Error:", err);
        process.exit(1);
    }
})();
