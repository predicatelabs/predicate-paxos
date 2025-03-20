export const SwapRouterABI = [
    {
      "inputs": [
        {
          "internalType": "contract IPoolManager",
          "name": "_poolManager",
          "type": "address"
        }
      ],
      "stateMutability": "nonpayable",
      "type": "constructor"
    },
    {
      "inputs": [],
      "name": "msgSender",
      "outputs": [
        {
          "internalType": "address",
          "name": "",
          "type": "address"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "components": [
            {
              "internalType": "Currency",
              "name": "currency0",
              "type": "address"
            },
            {
              "internalType": "Currency",
              "name": "currency1",
              "type": "address"
            },
            {
              "internalType": "uint24",
              "name": "fee",
              "type": "uint24"
            },
            {
              "internalType": "int24",
              "name": "tickSpacing",
              "type": "int24"
            },
            {
              "internalType": "contract IHooks",
              "name": "hooks",
              "type": "address"
            }
          ],
          "internalType": "struct PoolKey",
          "name": "key",
          "type": "tuple"
        },
        {
          "components": [
            {
              "internalType": "bool",
              "name": "zeroForOne",
              "type": "bool"
            },
            {
              "internalType": "int256",
              "name": "amountSpecified",
              "type": "int256"
            },
            {
              "internalType": "uint160",
              "name": "sqrtPriceLimitX96",
              "type": "uint160"
            }
          ],
          "internalType": "struct IPoolManager.SwapParams",
          "name": "params",
          "type": "tuple"
        },
        {
          "internalType": "bytes",
          "name": "hookData",
          "type": "bytes"
        }
      ],
      "name": "swap",
      "outputs": [
        {
          "components": [
            {
              "internalType": "int128",
              "name": "amount0",
              "type": "int128"
            },
            {
              "internalType": "int128",
              "name": "amount1",
              "type": "int128"
            }
          ],
          "internalType": "struct BalanceDelta",
          "name": "delta",
          "type": "tuple"
        }
      ],
      "stateMutability": "payable",
      "type": "function"
    }
];