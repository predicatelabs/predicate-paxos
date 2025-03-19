import { ethers } from "ethers";

export async function encodeBeforeSwap(
  sender: string,
  key: { Currency0: string; Currency1: string; Fee: number; TickSpacing: number; Hooks: string },
  params: { ZeroForOne: boolean; AmountSpecified: ethers.BigNumber; SqrtPriceLimitX96: ethers.BigNumber }
): Promise<string> {
  const abiCoder = new ethers.utils.AbiCoder();

  const paramTypes = [
    'address', 'address', 'address', 'uint24', 'int24', 'address', 'bool', 'int256', 'uint160'
  ];

  const values = [
    sender,
    key.Currency0, key.Currency1,
    key.Fee, key.TickSpacing, key.Hooks,
    params.ZeroForOne, params.AmountSpecified, params.SqrtPriceLimitX96
  ];

  const methodSig = "_beforeSwap(address,address,address,uint24,int24,address,bool,int256,uint160)";
  const selector = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(methodSig)).slice(0, 10);

  return selector + abiCoder.encode(paramTypes, values).slice(2);
}

export function encodeHookData(
  pm: { TaskId: string; ExpireByBlockNumber: ethers.BigNumber; SignerAddresses: string[]; Signatures: string[] },
  msgSender: string,
  msgValue: ethers.BigNumber
): string {
  const abiCoder = new ethers.utils.AbiCoder();

  const pmType = 'tuple(string,uint256,address[],bytes[])';

  const paramTypes = [pmType, 'address', 'uint256'];
  const values = [pm, msgSender, msgValue];


  return abiCoder.encode(paramTypes, values);
}

export async function getChainID(provider: ethers.providers.Provider): Promise<number> {
  const chainId = await provider.getNetwork();
  return chainId.chainId;
}

export function getECDSAKey(privateKeyStr: string): ethers.utils.SigningKey {
  const cleanKey = privateKeyStr.startsWith('0x') ? privateKeyStr.slice(2) : privateKeyStr;
  return new ethers.utils.SigningKey(cleanKey);
}

export async function waitForReceipt(provider: ethers.providers.Provider, txHash: string): Promise<ethers.providers.TransactionReceipt> {
  let receipt: ethers.providers.TransactionReceipt | null = null;
  while (receipt === null) {
    receipt = await provider.getTransactionReceipt(txHash);
    if (receipt === null) {
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
  return receipt;
}