import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();

  // Deploy the LedgityDataProvider library first
  const ledgityDataProviderLib = await deployments.deploy(
    "LedgityDataProvider",
    {
      from: deployer,
      log: true,
      waitConfirmations: 1,
    },
  );

  // Deploy the shared implementation with library linking
  await deployments.deploy("LedgityYieldVault_Implementation", {
    contract: "LedgityYieldVault",
    from: deployer,
    log: true,
    waitConfirmations: 1,
    libraries: {
      LedgityDataProvider: ledgityDataProviderLib.address,
    },
  });
}
