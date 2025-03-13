# Paxos USDL V4 Hooks

This repository contains the Uniswap V4 hook implementation for USDL (Lift Dollar), enabling policy-compliant trading via the Predicate Network.

## Architecture

![Architecture Diagram](assets/image.png)

This design consists of a router (necessary for swapping against the PoolManager), configuration for initializing two pools on the PoolManager, and two hooks.

#### AutoWrapper Hook
- Manages USDL ↔ wUSDL conversion operations
- Swaps against the underlying ERC20/wUSDL pool 
- Enforces zero-liquidity constraints on ghost pool
- Requires explicit liquid ERC20/wUSDL pool configuration

#### Predicate Hook
- Authorizes transactions on the liquid pool
- Enforces access control on liquid pool operations

## User Experience    
### Swapping wUSDL for an ERC20

To trade wUSDL, users must first be screened against the Paxos compliance policy. This is done by submitting a task to the Predicate Operator Network (see Integration Guide).
	- Screening is typically abstracted through a frontend interface
	- Median latency is ~250ms
	- A set of authorization signatures is returned from the Predicate API
	- These signatures must be embedded into the transaction’s hookData field
	- The transaction is then submitted to the Swap Router

### Swapping USDL Directly

Uniswap pools are not compatible with rebasing assets like USDL. Typically, users would be required to:
	•	Users must wrap USDL → wUSDL before swapping
	•	Or unwrap wUSDL → USDL after swapping (e.g., if receiving USDL from a USDC swap)

However, the AutoWrapperHook automates this process. Combined with the Ghost Pool, users can execute swaps involving USDL (e.g., USDL -> USDC or USDC -> USDL) in a single atomic transaction. Wrapping and unwrapping occur in-band.

⚠️ The same Predicate authorization is required for these swaps. The embedded hook data will be forwarded from the AutoWrapperHook to the PredicateHook to be validated. 


## Integration 

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

You should notice that your USDL balance has decreased by 5 USDL and USDC balance increased by 