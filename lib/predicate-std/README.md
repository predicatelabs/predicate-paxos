# Predicate

Solidity library for creating compliant smart contracts application (e.g. Uniswap V4 hooks) using the Predicate network.

## Overview

### Installation

#### Foundry 
```
$ forge install PredicateLabs/predicate-std 
```

<details>

For a Uniswap V4 hook:

Add `@PredicateLabs/uniswap-hook/=lib/predicate-std/src/` in `remappings.txt`

<summary>Remappings</summary>

</details>

#### Hardhat

```
$ npm install @predicate/predicate-std
```

## Integration

Deploy a `PredicateWrapper` that enforces custom compliance logic (e.g. blacklist, KYC, etc.) before letting calls pass through to your hook.

## Disclaimer

This library is provided as-is, without any guarantees or warranties. Use at your own risk.
