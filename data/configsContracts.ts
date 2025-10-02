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

function toRay(amount: number, decimals = 0) {
  // @dev ex: amount 100 = 100% => 2 decimals
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
    ] || (deployedContracts as any)[stringChainId]?.[0]?.contracts?.[symbol];

  const address = fromTemp || fromDeps || fromDeployments;

  if (!address || !isAddress(address) || address === zeroAddress)
    throw Error("Token not found");

  return address as Address;
}

export function getParametersForVault(
  chainId: number,
  name: string,
  symbol: string,
  lToken: Address,
  stakeToken: Address,
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

  return [
    {
      name,
      symbol,
      lToken,
      stakeToken,
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
    feeRecipient: "0x0000000000000000000000000000000000000001",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    vaults: {
      lyUSD: {
        asset: dependencies["1"].USDC,
        liquidityBufferRate: toRay(10, 2),
        liquidityManager: "0x0000000000000000000000000000000000000001",
        aaveLendingPool: "0x0000000000000000000000000000000000000000",
        //
        highWaterMark: 0n, // default 1:1 ratio
        deploymentDelay: 1, // days
        yieldAPR: toRay(5, 2), // 5% APR in RAY
        managementFeeRate: toRay(0.2, 2), // 0.2% in RAY
        performanceFeeRate: toRay(2, 2), // 2% in RAY
        withdrawalFeeRate: toRay(0.05, 2), // 0.05% in RAY
        withdrawalGasFee: parseEther("0.001"),
      },
      // lyEUR: {},
    },
  },
};
