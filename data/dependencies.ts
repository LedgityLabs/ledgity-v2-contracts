import { Address } from "viem";

export const dependencies: {
  [chainId: string]: {
    LDY?: Address;
    USDC?: Address;
    EURC?: Address;
  };
} = {
  // Ethereum Mainnet
  "1": {
    LDY: "0x482dF7483a52496F4C65AB499966dfcdf4DDFDbc",
    USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  },
  // Arbitrum One
  "42161": {
    LDY: "0x999FAF0AF2fF109938eeFE6A7BF91CA56f0D07e1",
    USDC: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
  },
  // Sonic
  "146": {
    LDY: "0x9cFBf905a444B5c871f0B447e137e8Ce7EeD0BCE",
    USDC: "0x29219dd400f2Bf60E5a23d13Be72B486D4038894",
    EURC: "0xe715cbA7B5cCb33790ceBFF1436809d36cb17E57",
  },
  // Hedera
  "295": {
    LDY: "0x9588f69388E905Dc55cF36f70c769da96aeE069F",
    USDC: "0x000000000000000000000000000000000006f89a",
  },
  // Linea
  "59144": {
    USDC: "0x176211869cA2b568f2A7D4EE941E073a821EE1ff",
  },
  // Base
  "8453": {
    LDY: "0x055d20a70eFd45aB839Ae1A39603D0cFDBDd8a13",
    USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    EURC: "0x60a3e35cc302bfa44cb288bc5a4f316fdb1adb42",
  },
};
