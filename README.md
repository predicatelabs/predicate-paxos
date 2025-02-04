# A Compliant, Decentralized Exchange

This is a simple Uniswap V4 hook that enforces a compliance policy on the swaps using the Predicate network.

## Deploy

Deploying Uniswap V4 on Unichain Sepolia:

```solidity
forge script script/DeployPredicateUniswap.sol:DeployPredicateUniswap --rpc-url unichain-sepolia --broadcast
```

