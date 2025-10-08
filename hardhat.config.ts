import "hardhat-contract-sizer";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";

// Tasks
import "./tasks/verify";
import "./tasks/extract-abis";
import "./tasks/deploy-mock-ccip-token";

import fs from "fs";
import { utils, Wallet } from "ethers";
// Types
import { type HardhatUserConfig } from "hardhat/config";
import { HardhatNetworkUserConfig, HttpNetworkUserConfig } from "hardhat/types";
import "./types/bigIntString";

import dotenv from "dotenv";
import colors from "colors";
dotenv.config();
colors.enable();

const {
  ETHERSCAN_API_KEY,
  HARDHAT_DEPLOY_FORK,
  DEPLOYER_PK,
  //
  MAINNET_RPC_URL,
  MAINNET_FORKING_BLOCK,
  BASE_RPC_URL,
  BASE_FORKING_BLOCK,
  SONIC_RPC_URL,
  SONIC_FORKING_BLOCK,
  LINEASCAN_RPC_URL,
  LINEASCAN_FORKING_BLOCK,
  ARBITRUM_RPC_URL,
  ARBITRUM_FORKING_BLOCK,
  HEDERA_RPC_URL,
  HEDERA_FORKING_BLOCK,
  HEDERA_VERIFY_API_KEY,
} = process.env;

if (!DEPLOYER_PK) throw Error("DEPLOYER_PK not found in environment variables");

// Fork Validation
const forkTarget = HARDHAT_DEPLOY_FORK?.toLowerCase();
if (forkTarget === "mainnet" && (!MAINNET_RPC_URL || !ETHERSCAN_API_KEY))
  throw Error("Mainnet config not found in environment variables");
if (forkTarget === "base" && (!BASE_RPC_URL || !ETHERSCAN_API_KEY))
  throw Error("Base config not found in environment variables");
if (forkTarget === "sonic" && (!SONIC_RPC_URL || !ETHERSCAN_API_KEY))
  throw Error("Sonic config not found in environment variables");
if (forkTarget === "hedera" && (!HEDERA_RPC_URL || !HEDERA_VERIFY_API_KEY))
  throw Error("Hedera config not found in environment variables");
if (forkTarget === "linea" && (!LINEASCAN_RPC_URL || !ETHERSCAN_API_KEY))
  throw Error("LineaScan config not found in environment variables");
if (forkTarget === "arbitrum" && (!ARBITRUM_RPC_URL || !ETHERSCAN_API_KEY))
  throw Error("Arbitrum config not found in environment variables");

/// @dev Create the temp file to write token deployments
if (!fs.existsSync("temp/deployedTokens.json")) {
  fs.mkdirSync("temp");
  fs.writeFileSync("temp/deployedTokens.json", "{}", "utf8");
}

// Centralized network configuration
interface NetworkConfig {
  chainId: number;
  name: string;
  rpcUrl: string;
  verifyApiKey: string;
  forkingBlock?: string;
  apiURL: string;
  browserURL: string;
  deploy?: string[];
  isTestnet?: boolean;
}

export const networkConfigs: { [key: string]: NetworkConfig } = {
  mainnet: {
    name: "mainnet",
    chainId: 1,
    rpcUrl: MAINNET_RPC_URL || "",
    verifyApiKey: ETHERSCAN_API_KEY || "",
    forkingBlock: MAINNET_FORKING_BLOCK || "",
    apiURL: "https://api.etherscan.io/v2/api?chainid=1",
    browserURL: "https://etherscan.io",
    deploy: ["deployers/protocol-v2/mainnet"],
  },
  base: {
    name: "base",
    chainId: 8453,
    rpcUrl: BASE_RPC_URL || "",
    verifyApiKey: ETHERSCAN_API_KEY || "",
    forkingBlock: BASE_FORKING_BLOCK,
    apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
    browserURL: "https://basescan.org",
    deploy: ["deployers/protocol-v2/base"],
  },
  sonic: {
    name: "sonic",
    chainId: 146,
    rpcUrl: SONIC_RPC_URL || "",
    verifyApiKey: ETHERSCAN_API_KEY || "",
    forkingBlock: SONIC_FORKING_BLOCK,
    apiURL: "https://api.etherscan.io/v2/api?chainid=146",
    browserURL: "https://sonicscan.org",
    deploy: ["deployers/protocol-v2/sonic"],
  },
  hedera: {
    name: "hedera",
    chainId: 295,
    rpcUrl: HEDERA_RPC_URL || "",
    verifyApiKey: HEDERA_VERIFY_API_KEY || "",
    forkingBlock: HEDERA_FORKING_BLOCK,
    apiURL: "https://server-verify.hashscan.io",
    browserURL: "https://hashscan.io/mainnet/",
    deploy: ["deployers/protocol-v2/hedera"],
  },
  arbitrum: {
    name: "arbitrumOne",
    chainId: 42161,
    rpcUrl: ARBITRUM_RPC_URL || "",
    verifyApiKey: ETHERSCAN_API_KEY || "",
    forkingBlock: ARBITRUM_FORKING_BLOCK,
    apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
    browserURL: "https://arbiscan.io",
    deploy: ["deployers/protocol-v2/arbitrum"],
  },
  linea: {
    name: "linea",
    chainId: 59144,
    rpcUrl: LINEASCAN_RPC_URL || "",
    verifyApiKey: ETHERSCAN_API_KEY || "",
    forkingBlock: LINEASCAN_FORKING_BLOCK,
    apiURL: "https://api.etherscan.io/v2/api?chainid=59144",
    browserURL: "https://lineascan.build",
    deploy: ["deployers/protocol-v2/linea"],
  },
};

function makeForkConfig(
  chainName: string | undefined,
): { hardhat: HardhatNetworkUserConfig } | {} {
  if (!chainName) return {};

  const config = networkConfigs[chainName];

  const blockNumber =
    config.forkingBlock === "latest" || !config.forkingBlock
      ? undefined
      : Number(config.forkingBlock);

  console.log(
    "=> Hardhat configured to fork".magenta,
    chainName.cyan,
    config.forkingBlock
      ? `${"at block".magenta} ${config.forkingBlock.cyan}`
      : "",
    "with deployer".magenta,
    new Wallet(DEPLOYER_PK as string).address.cyan,
  );

  /// @dev Nested structure to be destructured safely in case there is no fork
  return {
    hardhat: {
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
        interval: 1,
        mempool: {
          order: "fifo",
        },
      },
      accounts: [
        {
          privateKey: DEPLOYER_PK as string,
          balance: utils.parseEther("100000").toString(),
        },
      ],
    },
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
      accounts: [DEPLOYER_PK],
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

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    overrides: {
      "src/protocol-v2/LedgityYieldVault.sol": {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    },
    compilers: [
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "./deployers",
    deployments: "./deployers/deployments",
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  networks: {
    ...makeForkConfig(forkTarget),
    ...networks,
  },
  // Generate etherscan config from networkConfigs
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
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
  },
};

export default config;
