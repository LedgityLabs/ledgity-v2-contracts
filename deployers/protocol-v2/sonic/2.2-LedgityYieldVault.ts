import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy LedgityYieldVault".cyan);
  const { deployer } = await getNamedAccounts();

  // Deploy LedgityDataProvider, the withdrawal request views read from the vaults
  console.log("==> Deploy LedgityDataProvider".cyan);
  await deployments.deploy("LedgityDataProvider", {
    from: deployer,
    log: true,
    waitConfirmations: 3,
  });

  // Deploy the shared implementation
  await deployments.deploy("LedgityYieldVaultSonic_Implementation", {
    contract: "LedgityYieldVaultSonic",
    from: deployer,
    log: true,
    waitConfirmations: 3,
  });
}
