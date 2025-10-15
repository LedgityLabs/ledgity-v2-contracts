import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy LedgityYieldVault".cyan);
  const { deployer } = await getNamedAccounts();

  // Deploy the LedgityDataProvider library first
  console.log("==> Deploy lib LedgityDataProvider".cyan);
  const ledgityDataProviderLib = await deployments.deploy(
    "LedgityDataProvider",
    {
      from: deployer,
      log: true,
      waitConfirmations: 3,
    },
  );

  // Deploy the shared implementation with library linking
  await deployments.deploy("LedgityYieldVault_Implementation", {
    contract: "LedgityYieldVault",
    from: deployer,
    log: true,
    waitConfirmations: 3,
    libraries: {
      LedgityDataProvider: ledgityDataProviderLib.address,
    },
  });
}
