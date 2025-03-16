# Paxos USDL V4 Hooks

This repository contains the Uniswap V4 hook implementation for USDL (Lift Dollar), enabling policy-enforced swapping via the Predicate Network.

## Architecture

![Architecture Diagram](assets/image.png)

This design consists of a router (necessary for swapping against the PoolManager), configuration for initializing two pools on the PoolManager, and the two associated hooks.

#### Predicate Message 
- A struct unique to the Predicate Network
- Contains the necessary Predicate Operator-signed parameters for a transaction

#### Predicate Hook
- Requires a valid Predicate message on the liquid ERC20/wUSDL pool

#### AutoWrapper Hook
- Makes it possible to swap the rebasing asset (USDL) with one transaction
- Wraps and unwraps USDL ↔ wUSDL
- Swaps against the configured ERC20/wUSDL pool 

## User Experience    
### Swapping 

To swap assets, users must first be screened against the Paxos policy by registered Predicate Operators. This is done by fetching respective signatures for each transaction from the Predicate API before submitting it on-chain. 

Each task requests can be as fast as ~200ms and returns the following response (example);

```json
{
  "is_compliant": true | false,
  "signers": [
    "0xab..cd" 
  ],
  "signature": [
    "0xabe..e1cc1c"
  ],
  "expiry_block": 22033977,
  "task_id": "fedd253f-2317-48c2-b521-42828f40374c"
}
 ```

 These signatures must be nested into the HookData (see the integration section below) before the user's wallet is invoked. 


## Integration 

#### Frontend
TODO

#### Proxy Backend 
TODO

## Manual Test

Under /transactor, you will find well documented script which leverages the `predicate-sdk` to fetch signatures and swap against a mainnet USDL/USDC pool. Below are the instructions for running it!

1. Install and set variables
    ```bash
    # Navigate to the transactor directory
    cd transactor

    # Install dependencies
    npm install

    # Copy and configure environment variables
    cp .env.example .env
    ```

2. Deploy & Fund the Pool
    
    ⚠️ Use a private key which holds USDL and USDC
    ```bash 
    forge script script/DeployPaxosUSDLPools.sol:DeployPaxosUSDLPools --rpc-url {ethereum_rpc_url} --usdl 5 --usdc 5 --broadcast
    ```

3. Run the Transactor
    
    ```bash
        npm run swap --usdl 5
    ```

You should notice that your USDL balance has decreased by 5 USDL and USDC balance increased by the same amount.