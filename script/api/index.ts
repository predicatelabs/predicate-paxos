import * as dotenv from 'dotenv';
import { ethers } from 'ethers';
import axios from 'axios';

const ABI_FRAGMENT = [
    "function increment(tuple(string taskId, uint256 expireByBlockNumber, address[] signerAddresses, bytes[] signatures) predicateMessage) public payable"
];

async function main() {
    dotenv.config();

    const PRIVATE_KEY = process.env.PRIVATE_KEY!;
    const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
    const PREDICATE_API_KEY = process.env.API_KEY!;
    const PREDICATE_API_URL = process.env.API_URL || 'http://0.0.0.0:80/task';
    const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS!;

    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    try {
        const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI_FRAGMENT, wallet);

        const functionSignature = ethers.id("_increment()").slice(0, 10);
        const abiCoder = new ethers.AbiCoder();

        const txData = functionSignature;

        const response = await axios.post(
            PREDICATE_API_URL,
            {
                to: CONTRACT_ADDRESS,
                from: wallet.address,
                data: txData,
                value: "0"
            },
            {
                headers: {
                    'Content-Type': 'application/json',
                    'x-api-key': PREDICATE_API_KEY
                }
            }
        );

        console.log('API response:', response.data);
        const { task_id, signers, signature, expiry_block } = response.data;

        if (!signature || !signers) {
            throw new Error('Invalid API response');
        }

        const tx = await contract.increment(
            {
                taskId: task_id,
                expireByBlockNumber: expiry_block,
                signerAddresses: signers,
                signatures: signature
            },
            {
                gasLimit: 200000
            }
        );

        console.log('Transaction submitted:', tx.hash);
        const receipt = await tx.wait();
        console.log('Transaction status:', receipt.status === 1 ? 'success' : 'failed');

    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

main();