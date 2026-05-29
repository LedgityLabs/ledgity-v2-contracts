import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy FixedTermInvestmentVault".cyan);
  const { deployer } = await getNamedAccounts();

  // Retrieve or deploy LedgityDataProvider library
  const ledgityDataProviderLib =
    (await deployments.get("LedgityDataProvider")) ||
    (await deployments.deploy("LedgityDataProvider", {
      from: deployer,
      log: true,
      waitConfirmations: 3,
    }));

  // Deploy the shared implementation with library linking
  await deployments.deploy("FixedTermInvestmentVault_Implementation", {
    contract: "FixedTermInvestmentVault",
    from: deployer,
    log: true,
    waitConfirmations: 3,
    skipIfAlreadyDeployed: true,
    libraries: {
      LedgityDataProvider: ledgityDataProviderLib.address,
    },
  });
}
