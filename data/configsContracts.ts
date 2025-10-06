import fs from "fs";
import { Address, parseEther, parseUnits, zeroAddress, isAddress } from "viem";
import { dependencies } from "./dependencies";
import deployedContracts from "./deployments.json";

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
  highWaterMark: bigint;
  yieldAPR: bigint;
  managementFeeRate: bigint;
  performanceFeeRate: bigint;
  withdrawalFeeRate: bigint;
  withdrawalGasFee: bigint;
  deploymentDelay: number;
};

const TEMP_TOKENS_FILE = "temp/deployedTokens.json";

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

  const address = fromTemp || fromDeps || fromDeployments;

  if (
    !address ||
    !isAddress(address) ||
    (address === zeroAddress && !allowZeroAddress)
  )
    throw Error("Token not found");

  return address as Address;
}

export function getParametersForVault(
  chainId: number,
  name: string,
  symbol: "lyUSD" | "lyEUR",
  globalOwner: Address,
  globalPause: Address,
  globalAccessList: Address,
): [VaultParams, VaultLiquidityInitParams] {
  const chainConfig = configsContracts[chainId];
  const vaultConfig = chainConfig?.vaults?.[symbol];

  if (!chainConfig || !vaultConfig) throw Error("Vault not found");
  if (!vaultConfig.asset) throw Error("Asset not found");

  if (
    vaultConfig.liquidityManager === zeroAddress ||
    chainConfig.feeRecipient === zeroAddress
  )
    throw Error("Invalid liquidityManager or feeRecipient");

  const lTokenSymbol = symbol === "lyUSD" ? "LUSDC" : "LEURC";

  return [
    {
      name,
      symbol,
      lToken: getTokenAddress(chainId, lTokenSymbol, true),
      stakeToken: getTokenAddress(chainId, "LDY", true),
      globalOwner,
      globalPause,
      globalAccessList,
      //
      stakeForFeeReduction: chainConfig.stakeForFeeReduction,
      stakeForInstantWithdrawal: chainConfig.stakeForInstantWithdrawal,
      feeRecipient: chainConfig.feeRecipient,
      //
      asset: vaultConfig.asset,
      liquidityManager: vaultConfig.liquidityManager,
      liquidityBufferRate: vaultConfig.liquidityBufferRate,
      aaveLendingPool: vaultConfig.aaveLendingPool,
    },
    {
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
    vaults: {
      [symbol: string]: {
        asset: Address | undefined;
        liquidityBufferRate: bigint;
        liquidityManager: Address;
        aaveLendingPool: Address;
        //
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
    vaults: {
      lyUSD: {
        asset: getTokenAddress(1, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[1].AAVE_LENDING_POOL,
        //
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
        liquidityBufferRate: toRay(5),
        liquidityManager: "0xF25a516CAF56895032b3f3eE842b45462Ff491c3",
        aaveLendingPool: dependencies[1].AAVE_LENDING_POOL,
        //
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
    vaults: {
      lyUSD: {
        asset: getTokenAddress(8453, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[8453].AAVE_LENDING_POOL,
        //
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
        liquidityBufferRate: toRay(5),
        liquidityManager: "0xF25a516CAF56895032b3f3eE842b45462Ff491c3",
        aaveLendingPool: dependencies[8453].AAVE_LENDING_POOL,
        //
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
    vaults: {
      lyUSD: {
        asset: getTokenAddress(42161, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[42161].AAVE_LENDING_POOL,
        //
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
    owner: "0x972c17D0adA071db4a0395505dD3Ad0a80809053",
    feeRecipient: "0x22F74606AC919A4CA912Ad787A9bf1093902f692",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    vaults: {
      lyUSD: {
        asset: getTokenAddress(295, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: "0x0000000000000000000000000000000000000000",
        //
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
    vaults: {
      lyUSD: {
        asset: getTokenAddress(59144, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[59144].AAVE_LENDING_POOL,
        //
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
    vaults: {
      lyUSD: {
        asset: getTokenAddress(146, "USDC"),
        liquidityBufferRate: toRay(10),
        liquidityManager: "0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac",
        aaveLendingPool: dependencies[146].AAVE_LENDING_POOL,
        //
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
