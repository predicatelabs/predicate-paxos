# Paxos V4 Hook

#### Compliant exchange of USDL on Uniswap V4 powered by [Predicate](https://docs.predicate.io).

![Paxos V4 Hook](assets/PaxosV4Hook.png)

## Overview

A Uniswap V4 Hook that enables Paxos to offer compliant, decentralized exchange of USDL/wUSDL within the Uniswap ecosystem. The hook uses Predicate to authorize transactions coming from an addresses in a certain jurisdiction and not on the OFAC sanctions list.


## Usage

#### Install dependencies:
```bash
make install
```

#### Reset and update submodules:
```bash
git submodule update --init --recursive && git config --local core.hooksPath .githooks/ && chmod +x .githooks/pre-commit
```

#### Run tests:
```bash
forge test
```

### Call the Predicate API

```typescript
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
```

## Deploy

In the `.env` file, set the following variables:

```bash
PRIVATE_KEY=private_key
RPC_URL=rpc_url
PREDICATE_API_KEY=predicate_api_key
HOOK_ADDRESS=hook_address
```

#### Ethereum:

```solidity
forge script script/DeployPaxosHook.sol:DeployPaxosHook --rpc-url ethereum --broadcast
```

For verification:

```bash
forge verify-contract --chain-id 1 --etherscan-api-key <your_etherscan_api_key> --watch --constructor-args $(cast abi-encode "constructor(address,string)" $PREDICATE_MANAGER $POLICY_ID) src/PaxosHook.sol:PaxosHook
```