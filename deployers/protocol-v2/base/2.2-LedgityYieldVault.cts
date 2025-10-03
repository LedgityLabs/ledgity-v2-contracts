import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();

  // Deploy the shared implementation
  await deployments.deploy("LedgityYieldVault", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    deterministicDeployment: true,
  });
}
