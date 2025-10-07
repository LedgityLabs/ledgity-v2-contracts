import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();

  // Deploy the LedgityDataProvider library first
  console.log("\n=> Deploy LedgityYieldVault.LedgityDataProvider lib".cyan);
  const ledgityDataProviderLib = await deployments.deploy(
    "LedgityDataProvider",
    {
      from: deployer,
      log: true,
      waitConfirmations: 3,
    },
  );

  // Deploy the shared implementation with library linking
  console.log("=> Deploy LedgityYieldVault".cyan);
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
