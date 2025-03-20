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
    currency0Address: "0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82",
    currency1Address: "0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0",
    routerAddress: "0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6",
    hookAddress: "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853",
    lpFees: 3000,
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
    .option("--hook-address <address>", "Hook address", config.hookAddress)
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
    hookAddress: options.hookAddress,
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
