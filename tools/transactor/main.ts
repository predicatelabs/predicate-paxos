import {Command} from "commander";
import * as dotenv from "dotenv";
import {createContext, runService} from "./service/service";
import process from "node:process";

dotenv.config();

const program = new Command();

interface Config {
    predicateApiUrl: string;
    apiKey: string;
    ethRpcUrl: string;
    privateKey: string;
    enviroment: string;
    currency0Adress: string;
    currency1Adress: string;
    routerAddress: string;
    hookAddress: string;
    lpFees: number;
    tickSpacing: number;
}

function getConfig(): Config {
    return {
        predicateApiUrl: process.env.PREDICATE_API_URL || 'http://0.0.0.0:80/task',
        apiKey: process.env.API_KEY || '',
        ethRpcUrl: process.env.ETH_RPC_URL || 'http://localhost:8545',
        privateKey: process.env.PRIVATE_KEY || 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        enviroment: process.env.ENVIRONMENT || 'local',
        currency0Adress: process.env.CURRENCY0_ADDRESS || '0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82',
        currency1Adress: process.env.CURRENCY1_ADDRESS || '0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0',
        routerAddress: process.env.SWAP_ROUTER_ADDRESS || '0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6',
        hookAddress: process.env.HOOK_ADDRESS || '0x18A5c776bdb3502C4172F8b5558281cf0060c080',
        lpFees: Number.parseInt(process.env.LP_FEES || '3000', 10),
        tickSpacing: Number.parseInt(process.env.TICK_SPACING || '60', 10),
    };

    
}

program
    .name('transactor')
    .description('Helper tool to transact with UniV4 Hook')
    .action(async () => {
        try {
            const config = getConfig();
            const ctx = createContext();
            await runService(ctx, config);
        } catch (err) {
            console.error('Error:', err);
            process.exit(1);
        }
    });

program.parse(process.argv);