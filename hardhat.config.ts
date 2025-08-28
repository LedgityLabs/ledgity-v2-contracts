// This file has a .cts extension, because Hardhat that's currently the only way to get
// hardhat to support ESM in TypeScript projects.
// See: https://hardhat.org/hardhat-runner/docs/advanced/using-esm
// And: https://github.com/NomicFoundation/hardhat/issues/3385

import "hardhat-contract-sizer";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "colors";

// Tasks
import "./tasks/verify.cts";
import "./tasks/deploy-mock-ccip-token.cts";

import { parseEther } from "ethers/lib/utils";
import { type HardhatUserConfig } from "hardhat/config";
import { HardhatNetworkUserConfig, HttpNetworkUserConfig } from "hardhat/types";

import dotenv from "dotenv";
import colors from "colors";
dotenv.config();
colors.enable();

const {
  HARDHAT_FORK_TARGET,
  DEPLOYER_PK,
  HEDERA_DEPLOYER_PK,
  MAINNET_RPC_URL,
  MAINNET_FORKING_BLOCK,
  MAINNET_VERIFY_API_KEY,
  BASE_RPC_URL,
  BASE_FORKING_BLOCK,
  BASE_VERIFY_API_KEY,
  SONIC_RPC_URL,
  SONIC_FORKING_BLOCK,
  SONIC_VERIFY_API_KEY,
  LINEASCAN_RPC_URL,
  LINEASCAN_FORKING_BLOCK,
  LINEASCAN_VERIFY_API_KEY,
  ARBITRUM_RPC_URL,
  ARBITRUM_FORKING_BLOCK,
  ARBITRUM_VERIFY_API_KEY,
  HEDERA_RPC_URL,
  HEDERA_FORKING_BLOCK,
  HEDERA_VERIFY_API_KEY,
} = process.env;

// Validation
if (!DEPLOYER_PK && !HEDERA_DEPLOYER_PK)
  throw Error("Deployer private key not found in environment variables");
if (!MAINNET_RPC_URL || !MAINNET_VERIFY_API_KEY)
  throw Error("Mainnet config not found in environment variables");
if (!BASE_RPC_URL || !BASE_VERIFY_API_KEY)
  throw Error("Base config not found in environment variables");
if (!SONIC_RPC_URL || !SONIC_VERIFY_API_KEY)
  throw Error("Sonic config not found in environment variables");
if (!HEDERA_RPC_URL || !HEDERA_VERIFY_API_KEY)
  throw Error("Hedera config not found in environment variables");
if (!LINEASCAN_RPC_URL || !LINEASCAN_VERIFY_API_KEY)
  throw Error("LineaScan config not found in environment variables");
if (!ARBITRUM_RPC_URL || !ARBITRUM_VERIFY_API_KEY)
  throw Error("Arbitrum config not found in environment variables");

// Centralized network configuration
interface NetworkConfig {
  chainId: number;
  name: string;
  rpcUrl: string;
  forkingBlock?: string;
  verifyApiKey: string;
  apiURL: string;
  browserURL: string;
  deploy?: string[];
  isTestnet?: boolean;
}

const networkConfigs: { [key: string]: NetworkConfig } = {
  mainnet: {
    name: "mainnet",
    chainId: 1,
    rpcUrl: MAINNET_RPC_URL,
    forkingBlock: MAINNET_FORKING_BLOCK,
    verifyApiKey: MAINNET_VERIFY_API_KEY,
    apiURL: "https://api.etherscan.io/api",
    browserURL: "https://etherscan.io",
    deploy: ["./contracts/hardhat/deploy-mainnet"],
  },
  base: {
    name: "base",
    chainId: 8453,
    rpcUrl: BASE_RPC_URL,
    forkingBlock: BASE_FORKING_BLOCK,
    verifyApiKey: BASE_VERIFY_API_KEY,
    apiURL: "https://api.basescan.org/api",
    browserURL: "https://basescan.org",
    deploy: ["./contracts/hardhat/deploy-base"],
  },
  sonic: {
    name: "sonic",
    chainId: 146,
    rpcUrl: SONIC_RPC_URL,
    forkingBlock: SONIC_FORKING_BLOCK,
    verifyApiKey: SONIC_VERIFY_API_KEY,
    apiURL: "https://api.sonicscan.org/api",
    browserURL: "https://sonicscan.org",
    deploy: ["./contracts/hardhat/deploy-sonic"],
  },
  hedera: {
    name: "hedera",
    chainId: 295,
    rpcUrl: HEDERA_RPC_URL,
    forkingBlock: HEDERA_FORKING_BLOCK,
    verifyApiKey: HEDERA_VERIFY_API_KEY,
    apiURL: "https://server-verify.hashscan.io",
    browserURL: "https://hashscan.io/mainnet/",
    deploy: ["./contracts/hardhat/deploy-hedera"],
  },
  arbitrum: {
    name: "arbitrumOne",
    chainId: 42161,
    rpcUrl: ARBITRUM_RPC_URL,
    forkingBlock: ARBITRUM_FORKING_BLOCK,
    verifyApiKey: ARBITRUM_VERIFY_API_KEY,
    apiURL: "https://api.arbiscan.io",
    browserURL: "https://arbiscan.io",
    deploy: ["./contracts/hardhat/deploy-arbitrum"],
  },
  linea: {
    name: "linea",
    chainId: 59144,
    rpcUrl: LINEASCAN_RPC_URL,
    forkingBlock: LINEASCAN_FORKING_BLOCK,
    verifyApiKey: LINEASCAN_VERIFY_API_KEY,
    apiURL: "https://api.lineascan.build/api",
    browserURL: "https://lineascan.build",
  },
};

// Fork configuration
const forkTarget = HARDHAT_FORK_TARGET?.toLowerCase();
if (!forkTarget || !networkConfigs[forkTarget]) {
  throw Error("Missing or erroneous fork target");
}

function makeForkConfig(chainName: string): HardhatNetworkUserConfig {
  const config = networkConfigs[chainName];
  const blockNumber =
    config.forkingBlock === "latest" || !config.forkingBlock
      ? undefined
      : Number(config.forkingBlock);

  console.log(
    `=> Hardhat forking ${chainName.toUpperCase()}${config.forkingBlock ? ` at block ${config.forkingBlock}` : ""}\n`
      .magenta,
  );

  return {
    chainId: config.chainId,
    deploy: config.deploy,
    saveDeployments: true,
    live: true,
    forking: {
      url: config.rpcUrl,
      blockNumber,
    },
    mining: {
      auto: true,
      mempool: {
        order: "fifo",
      },
    },
    accounts: [
      {
        privateKey: (chainName === "hedera"
          ? HEDERA_DEPLOYER_PK
          : DEPLOYER_PK) as string,
        balance: parseEther("100000").toString(),
      },
    ],
  };
}

// Generate networks config from networkConfigs
const networks = Object.entries(networkConfigs).reduce(
  (
    acc: {
      [key: string]: HttpNetworkUserConfig;
    },
    [name, data],
  ) => {
    acc[name] = {
      chainId: data.chainId,
      url: data.rpcUrl,
      accounts: [
        (name === "hedera" ? HEDERA_DEPLOYER_PK : DEPLOYER_PK) as string,
      ],
      saveDeployments: true,
      deploy: data.deploy,
      verify: {
        etherscan: {
          apiKey: data.verifyApiKey,
          apiUrl: data.apiURL,
        },
      },
    };
    return acc;
  },
  {},
);

// Generate etherscan config from networkConfigs
const etherscan = {
  apiKey: Object.entries(networkConfigs).reduce(
    (
      acc: {
        [key: string]: string;
      },
      [_, data],
    ) => {
      acc[data.name] = data.verifyApiKey;
      return acc;
    },
    {},
  ),
  customChains: Object.values(networkConfigs)
    .filter((data) => data.name !== "mainnet")
    .map((data) => ({
      network: data.name,
      chainId: data.chainId,
      urls: {
        apiURL: data.apiURL,
        browserURL: data.browserURL,
      },
    })),
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "./deployers/deploy",
    deployments: "./deployers/deployments",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    hardhat: makeForkConfig(forkTarget),
    ...networks,
  },
  etherscan,
  defaultNetwork: "hardhat",
};

export default config;
