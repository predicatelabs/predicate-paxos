# Paxos V4 Hook

#### Compliant exchange of USDL on Uniswap V4 powered by [Predicate](https://docs.predicate.io).

![Paxos V4 Hook](assets/PaxosV4Hook.png)

## Overview

A Uniswap V4 Hook that enables Paxos to offer compliant, decentralized exchange of USDL/wUSDL within the Uniswap ecosystem. The hook uses Predicate to authorize transactions coming from an addresses in a certain jurisdiction and not on the OFAC sanctions list.


## Usage

```bash
forge build
```

## Deploy

#### Unichain Sepolia:

```solidity
forge script script/DeployPaxosV4Hook.sol:DeployPaxosV4Hook --rpc-url unichain-sepolia --broadcast
```