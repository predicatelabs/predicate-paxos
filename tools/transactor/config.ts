// src/config.ts
import { utils } from "ethers";

export interface Config {
    predicateAPIURL: string;
    apiKey: string;
    environment: string;
    ethRPCURL: string;
    privateKey: string;
    routerAddress: string;
    hookAddress: string;
    lpFees: number;
    tickSpacing: number;
    currency0Address: string;
    currency1Address: string;
}

export function validateConfig(cfg: Config): void {
    if (!cfg.predicateAPIURL) {
        throw new Error("predicate API URL is required");
    }
    if (!cfg.environment) {
        throw new Error("environment is required");
    }
    if (!cfg.ethRPCURL) {
        throw new Error("ethereum RPC URL is required");
    }
    if (!cfg.privateKey) {
        throw new Error("private key is required");
    }
    if (!cfg.tickSpacing) {
        throw new Error("tick spacing is required");
    }
    if (!cfg.currency0Address || !utils.isAddress(cfg.currency0Address)) {
        throw new Error(
            "currency0 address is required and must be a valid Ethereum address",
        );
    }
    if (!cfg.currency1Address || !utils.isAddress(cfg.currency1Address)) {
        throw new Error(
            "currency1 address is required and must be a valid Ethereum address",
        );
    }
    if (!cfg.routerAddress || !utils.isAddress(cfg.routerAddress)) {
        throw new Error(
            "swap router address is required and must be a valid Ethereum address",
        );
    }
    if (!cfg.hookAddress || !utils.isAddress(cfg.hookAddress)) {
        throw new Error(
            "hook address is required and must be a valid Ethereum address",
        );
    }
}
