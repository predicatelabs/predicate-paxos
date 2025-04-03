// src/main.ts
import { Command } from "commander";
import { TransactorService } from "./service";
import { validateConfig } from "./config";
import type { Config } from "./config";

const program = new Command();

let config: Config = {
    predicateAPIURL: "http://0.0.0.0:80/task",
    apiKey: "x",
    ethRPCURL: "http://localhost:8545",
    privateKey:
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    environment: "local",
    currency0Address: "0x742489F22807ebB4C36ca6cD95c3e1C044B7B6c8",
    currency1Address: "0xA9e6Bfa2BF53dE88FEb19761D9b2eE2e821bF1Bf",
    routerAddress: "0x8A791620dd6260079BF849Dc5567aDC3F2FdC318",
    predicateHookAddress: "0x6578E2c3F87C3270282F7fe4E63Dfb684a496880",
    autoWrapperAddress: "0x787Ae5950b1F2665bE9D9e6F9cE03a27A19da888",
    lpFees: 0,
    tickSpacing: 60,
    amount: "",
};

program
    .option(
        "--predicateApiUrl <url>",
        "Predicate API URL",
        config.predicateAPIURL,
    )
    .option("--apiKey <key>", "API key", config.apiKey)
    .option("--ethRpcUrl <url>", "Ethereum RPC URL", config.ethRPCURL)
    .option("--privateKey <key>", "Private key", config.privateKey)
    .option("--environment <env>", "Environment", config.environment)
    .option(
        "--currency0Address <address>",
        "Currency0 address",
        config.currency0Address,
    )
    .option(
        "--currency1Address <address>",
        "Currency1 address",
        config.currency1Address,
    )
    .option(
        "--routerAddress <address>",
        "Swap router address",
        config.routerAddress,
    )
    .option(
        "--predicateHookAddress <address>",
        "Predicate hook address",
        config.predicateHookAddress,
    )
    .option(
        "--autoWrapperAddress <address>",
        "Auto wrapper address",
        config.autoWrapperAddress,
    )
    .option(
        "--lpFees <number>",
        "LP fees",
        (val: string) => Number.parseInt(val),
        config.lpFees,
    )
    .option(
        "--tickSpacing <number>",
        "Tick spacing",
        (val: string) => Number.parseInt(val),
        config.tickSpacing,
    )
    .option(
        "--amount <string>",
        "Swap amount in wei",
        config.amount,
    );

program.parse(process.argv);
const options = program.opts();

config = {
    ...config,
    predicateAPIURL: options.predicateApiUrl,
    apiKey: options.apiKey,
    ethRPCURL: options.ethRpcUrl,
    privateKey: options.privateKey,
    environment: options.environment,
    currency0Address: options.currency0Address,
    currency1Address: options.currency1Address,
    routerAddress: options.routerAddress,
    predicateHookAddress: options.predicateHookAddress,
    autoWrapperAddress: options.autoWrapperAddress,
    lpFees: options.lpFees,
    tickSpacing: options.tickSpacing,
    amount: options.amount,
};

try {
    validateConfig(config);
} catch (err: unknown) {
    console.error("Configuration error:", err instanceof Error ? err.message : String(err));
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
