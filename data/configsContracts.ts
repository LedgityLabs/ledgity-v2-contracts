import { Address, parseEther, parseUnits } from "viem";
import { dependencies } from "./dependencies";

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

function toRay(amount: number, decimals = 0) {
  // @dev ex: amount 100 = 100% => 2 decimals
  return parseUnits(amount.toString(), 27 - decimals);
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
      liquidityManager: chainConfig.liquidityManager,
      feeRecipient: chainConfig.feeRecipient,
      //
      asset: vaultConfig.asset,
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
    liquidityManager: Address;
    feeRecipient: Address;
    stakeForFeeReduction: bigint;
    stakeForInstantWithdrawal: bigint;
    vaults: {
      [symbol: string]: {
        asset: Address | undefined;
        liquidityBufferRate: bigint;
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
  [1]: {
    liquidityManager: "0x0000000000000000000000000000000000000000",
    feeRecipient: "0x0000000000000000000000000000000000000000",
    stakeForFeeReduction: 0n,
    stakeForInstantWithdrawal: 0n,
    vaults: {
      lyUSD: {
        asset: dependencies["1"].USDC,
        liquidityBufferRate: toRay(10, 2),
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
