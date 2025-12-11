import fs from "fs";
import {
  Address,
  parseEther,
  parseUnits,
  zeroAddress,
  isAddress,
  createPublicClient,
  http,
} from "viem";
import { dependencies } from "./dependencies";
import deployedContracts from "./deployments.json";
import { base } from "viem/chains";

type VaultParams = {
  name: string;
  symbol: string;
  asset: Address;
  lToken: Address;
  stakeToken: Address;
  stakeForFeeReduction: bigint;
  stakeForInstantWithdrawal: bigint;
  globalOwner: Address;
  globalPause: Address;
  globalAccessList: Address;
  liquidityManager: Address;
  feeRecipient: Address;
  liquidityBufferRate: bigint;
  aaveLendingPool: Address;
};

type VaultLiquidityInitParams = {
  initialAssetsPerShare: bigint;
  highWaterMark: bigint;
  yieldAPR: bigint;
  managementFeeRate: bigint;
  performanceFeeRate: bigint;
  withdrawalFeeRate: bigint;
  withdrawalGasFee: bigint;
  deploymentDelay: number;
};

const TEMP_TOKENS_FILE = "temp/deployedTokens.json";
const FOUR_YEARS_IN_SECONDS = BigInt(4 * 365 * 24 * 60 * 60);
const EMPTY_MERKLE_ROOT =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

function toRay(amount: number, decimals = 2) {
  // @dev ex: amount = 100 & decimals = 2 => 100%
  return parseUnits(amount.toString(), 27 - decimals);
}

export function writeTempTokenAddress(
  chainId: number | string,
  symbol: string,
  address: string,
) {
  if (!fs.existsSync(TEMP_TOKENS_FILE)) {
    fs.mkdirSync("temp");
    fs.writeFileSync(TEMP_TOKENS_FILE, "{}", "utf8");
  }

  const deployedTokens: {
    [chainId: string]: {
      [symbol: string]: string;
    };
  } = JSON.parse(fs.readFileSync(TEMP_TOKENS_FILE, "utf8"));

  const stringChainId = chainId.toString();

  deployedTokens[stringChainId] ??= {};
  deployedTokens[stringChainId][symbol] = address;

  fs.writeFileSync(
    TEMP_TOKENS_FILE,
    JSON.stringify(deployedTokens, null, 2),
    "utf8",
  );
}

export async function getReferenceBaseAssetsPerShare(
  symbol: "lyUSD" | "lyEUR",
): Promise<bigint> {
  const client = createPublicClient({
    chain: base,
    transport: http(base.rpcUrls.default.http[0]),
  });

  const result = await client.readContract({
    abi: [
      {
        type: "function",
        inputs: [{ name: "shares", internalType: "uint256", type: "uint256" }],
        name: "convertToAssets",
        outputs: [{ name: "assets", internalType: "uint256", type: "uint256" }],
        stateMutability: "view",
      },
    ],
    address: getTokenAddress(8453, symbol),
    functionName: "convertToAssets",
    args: [10n ** 18n],
  });

  return result;
}

export function getTokenAddress(
  chainId: number | string,
  symbol: string,
  allowZeroAddress = false,
): Address {
  const stringChainId = chainId.toString();

  const fromDeps = (dependencies as any)[stringChainId]?.[symbol];
  const fromTemp = fs.existsSync(TEMP_TOKENS_FILE)
    ? JSON.parse(fs.readFileSync(TEMP_TOKENS_FILE, "utf8"))?.[stringChainId]?.[
        symbol
      ]
    : undefined;
  const fromDeployments =
    (deployedContracts as any)[stringChainId]?.[0]?.contracts?.[
      `${symbol}_Proxy`
    ]?.address ||
    (deployedContracts as any)[stringChainId]?.[0]?.contracts?.[symbol]
      ?.address;

  const address = fromTemp || fromDeps || fromDeployments || zeroAddress;

  if (
    !address ||
    !isAddress(address) ||
    (address === zeroAddress && !allowZeroAddress)
  )
    throw Error(`Token ${symbol} not found for chain ${chainId}`);

  return address as Address;
}

export function getGeneralChainConfig(chainId: number) {
  const chainConfig = configsContracts[chainId];

  if (!chainConfig) throw Error("Chain not found");

  return chainConfig;
}

export async function getParametersForVault(
  chainId: number,
  name: string,
  symbol: "lyUSD" | "lyEUR",
  globalOwner: Address,
  globalPause: Address,
  globalAccessList: Address,
): Promise<[VaultParams, VaultLiquidityInitParams]> {
  const chainConfig = configsContracts[chainId];
  const vaultConfig = chainConfig?.vaults?.[symbol];

  if (!chainConfig || !vaultConfig) throw Error("Vault not found");
  if (!vaultConfig.asset) throw Error("Asset not found");

  if (
    vaultConfig.liquidityManager === zeroAddress ||
    chainConfig.feeRecipient === zeroAddress
  )
    throw Error("Invalid liquidityManager or feeRecipient");

  const referenceBaseAssetsPerShare =
    await getReferenceBaseAssetsPerShare(symbol);
  const initialAssetsPerShare =
    vaultConfig.initialAssetsPerShare || referenceBaseAssetsPerShare;
  console.log("=> Initial Share Price: ", initialAssetsPerShare);

  return [
    {
      name,
      symbol,
      stakeToken: chainConfig.stakeToken,
      globalOwner,
      globalPause,
      globalAccessList,
      //
      stakeForFeeReduction: chainConfig.stakeForFeeReduction,
      stakeForInstantWithdrawal: chainConfig.stakeForInstantWithdrawal,
      feeRecipient: chainConfig.feeRecipient,
      //
      lToken: vaultConfig.lToken,
      asset: vaultConfig.asset,
      liquidityManager: vaultConfig.liquidityManager,
      liquidityBufferRate: vaultConfig.liquidityBufferRate,
      aaveLendingPool: vaultConfig.aaveLendingPool,
    },
    {
      initialAssetsPerShare,
      highWaterMark: vaultConfig.highWaterMark,
      deploymentDelay: vaultConfig.deploymentDelay,
      yieldAPR: vaultConfig.yieldAPR,
      managementFeeRate: vaultConfig.managementFeeRate,
      performanceFeeRate: vaultConfig.performanceFeeRate,
      withdrawalFeeRate: vaultConfig.withdrawalFeeRate,
      withdrawalGasFee: vaultConfig.withdrawalGasFee,
    },
  ];
}

const configsContracts: {
  [chainId: string]: {
    owner: Address;
    feeRecipient: Address;
    stakeForFeeReduction: bigint;
    stakeForInstantWithdrawal: bigint;
    stakeToken: Address;
    maxLockDurationSeconds: bigint;
    initialMerkleRoot: string;
    vaults: {
      [symbol: string]: {
        asset: Address | undefined;
        lToken: Address;
        liquidityBufferRate: bigint;
        liquidityManager: Address;
        aaveLendingPool: Address;
        //
        initialAssetsPerShare: bigint;
        highWaterMark: bigint;
        deploymentDelay: number;
        yieldAPR: bigint;
        managementFeeRate: bigint;
        performanceFeeRate: bigint;
        withdrawalFeeRate: bigint;
        withdrawalGasFee: bigint;
      };
    };
  };
} = {
  // Ethereum
  [1]: {
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(1, "LDY"),
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(1, "USDC"),
        lToken: getTokenAddress(1, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[1].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: parseEther("0.001"),
      },
      lyEUR: {
        asset: getTokenAddress(1, "EURC"),
        lToken: getTokenAddress(1, "LEURC", true),
        liquidityBufferRate: toRay(5),
        liquidityManager: "0xF25a516CAF56895032b3f3eE842b45462Ff491c3",
        aaveLendingPool: dependencies[1].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: parseEther("0.001"),
      },
    },
  },
  // Base
  [8453]: {
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(8453, "LDY"),
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(8453, "USDC"),
        lToken: getTokenAddress(8453, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[8453].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
      lyEUR: {
        asset: getTokenAddress(8453, "EURC"),
        lToken: getTokenAddress(8453, "LEURC", true),
        liquidityBufferRate: toRay(5),
        liquidityManager: "0xF25a516CAF56895032b3f3eE842b45462Ff491c3",
        aaveLendingPool: dependencies[8453].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
    },
  },
  // Arbitrum
  [42161]: {
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(42161, "LDY"),
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(42161, "USDC"),
        lToken: getTokenAddress(42161, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[42161].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
    },
  },
  // Hedera
  [295]: {
    owner: "0x000000000000000000000000000000000099304e",
    feeRecipient: "0x000000000000000000000000000000000099304e",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(295, "LDY"),
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(295, "USDC"),
        lToken: getTokenAddress(295, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0x0000000000000000000000000000000000993039",
        aaveLendingPool: "0x0000000000000000000000000000000000000000",
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
    },
  },
  // Linea
  [59144]: {
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(59144, "LDY", true), // No $LDY on Linea
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(59144, "USDC"),
        lToken: getTokenAddress(59144, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[59144].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
    },
  },
  // Sonic
  [146]: {
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    stakeToken: getTokenAddress(146, "LDY"),
    maxLockDurationSeconds: FOUR_YEARS_IN_SECONDS,
    initialMerkleRoot: EMPTY_MERKLE_ROOT,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(146, "USDC"),
        lToken: getTokenAddress(146, "LUSDC", true),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[146].AAVE_LENDING_POOL,
        //
        initialAssetsPerShare: 0n, // defaults to fetching Base vault price
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(9), // 9% APR in RAY
        managementFeeRate: 0n, // 0.2% in RAY
        performanceFeeRate: 0n, // 2% in RAY
        withdrawalFeeRate: toRay(0.3), // 0.05% in RAY
        withdrawalGasFee: 0n,
      },
    },
  },
};

const newvaults = {
  base: "0x76f1f8859A37c32d0764898F7f0B1585ed983f00",
  arbitrum: "0x5bAF90214294338838faD1AbdB7b928922660933",
  hedera: "0x17C925Ee24da3bfc7E1C85e765ACe0d6aEC1Bb37",
  linea: "0x20968165B7d2cDF33aF632aAB3e0539848d44BC8",
  mainnet: "0x6fFc9A91E8c87FBE3744cEB6A134537c6A21b411",
  sonic: "0x3Afcd7A95bffDE892F1f4670583B9d0911951F64",
};

// ARBITRUM
// "StakingPositions"  0x883108311b43871be1e590C1ab0979e1e72B1DF5
// "StakingRewardsDistributor"  0xEB4B058BF032E1eD61AA1fEcA332a8b8b96F7483

// BASE
// "StakingPositions"  0x4CAEE650C47462457eCa0D3411B8b633d828Fd2a
// "StakingRewardsDistributor"  0xB5f8754DD9cE92950872F033093043f0c0F9a384

// ETHEREUM
// "StakingPositions"  0xF2663B722E0FaCcC6fB2743AB8CB30B1d8d93649
// "StakingRewardsDistributor"  0xa87d32a42f208f428C186C4dbf6DE9D3F93dBa6f

// await fetch("https://api.krystal.app/all/v1/vaults/1/0x2f59e0aa5fce7898620f65621ab0f8e2bd308448", {
//     "credentials": "omit",
//     "headers": {
//         "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:146.0) Gecko/20100101 Firefox/146.0",
//         "Accept": "application/json, text/plain, */*",
//         "Accept-Language": "en,en-US;q=0.8,fr;q=0.5,fr-FR;q=0.3",
//         "Alt-Used": "api.krystal.app",
//         "Sec-Fetch-Dest": "empty",
//         "Sec-Fetch-Mode": "cors",
//         "Sec-Fetch-Site": "same-site",
//         "Priority": "u=4"
//     },
//     "referrer": "https://defi.krystal.app/",
//     "method": "GET",
//     "mode": "cors"
// });
