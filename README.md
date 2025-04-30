# USDL V4 Hook Suite

A Uniswap V4 hook implementation that enables policy-controlled trading of USDL (Lift Dollar) with automated token wrapping. 
Using [Predicate](https://predicate.io), the wUSDL/ERC20 V4 hook enforces configurable compliance requirements at the smart contract level. 

Ownership of the hooks is initially set to the deployer but can be transferred to any Ethereum address. 
The owner can update onchain allowlists and policies, which may include constraints such as transaction limits, geo-restrictions, 
and other compliance controls. An example policy is provided in this repository.

## Overview

This repository contains two custom Uniswap V4 hooks that work in tandem to enable policy-compliant trading of USDL:

1. **PredicateHook**: Enforces compliance policies on the liquid ERC20/wUSDL pool through the Predicate Network

2. **AutoWrapper**: Manages automatic wrapping/unwrapping of USDL ↔ wUSDL during swaps

*note*: the predicated pool is liquid and can be swapped against individually. 
The AutoWrapper hook is used to wrap/unwrap USDL ↔ wUSDL during swaps against the predicated pool; making it easier to swap USDL.

You can find the design doc [here](https://predicate-network.notion.site/Design-Doc-Paxos-Uniswap-V4-Hooks-1e3d742b36ac80968d5df0282292e1ba?pvs=74)

## Architecture

![Architecture Diagram](assets/architecture.png)

### Components

- **SimpleV4Router**: Handles swap routing and settlement with the Uniswap V4 PoolManager
- **Pools (configured with scripts)**:
   - Ghost Pool (USDL/ERC20)
   - Liquid Pool (wUSDL/ERC20)
- **Hook System**:
   - PredicateHook: Validates compliance through signed Predicate messages
   - AutoWrapper: Manages USDL conversion and routing between pools

## Policy

Policies are JSON objects stored onchain and evaluated by Predicate Operators offchain. Each policy contains a set of 
rules—such as AML checks, geofencing, or other criteria—which must be satisfied for a transaction to be authorized.

Contracts requiring policy validation must inherit from PredicateClient, which stores the policyId and interfaces with 
the PredicateManager to verify authorization at execution time.

Under script/ you will find an UpdatePolicy.s.sol-you can run it as follows:

```bash
# 🔔 You must have your .env file setup to run this script.
make update-policy --policy-id {policy-id}
```

## Deployment

### Prerequisites
- Node.js >=18
- Foundry 1.0.0
- An Ethereum node provider (e.g. Alchemy, Infura, etc.)

### Setup

```bash
# Install dependencies
make install

# Build contracts
make build

# Run tests
make tests
```

### Local Deployment

```bash
# Deploy full suite
make deploy-contracts

# Or deploy individual components
make deploy-pool-manager
make deploy-router
make deploy-predicate-hook
make deploy-tokens-and-liquidity-pool
make deploy-auto-wrapper
```

## Testing

### Unit Tests
```bash
forge test
```

### Integration Tests
```bash
# Deploy test environment
make deploy-contracts

# Run integration test suite
forge test --match-path test/integration/*
```

