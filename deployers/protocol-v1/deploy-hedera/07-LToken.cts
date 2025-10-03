import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();
  const aprHistory = await deployments.get("APRHistory");

  // Deploy the shared LToken implementation
  await deployments.deploy("LTokenHedera_Implementation", {
    contract: "LTokenHedera",
    from: deployer,
    log: true,
    waitConfirmations: 1,
    skipIfAlreadyDeployed: true,
    libraries: {
      APRHistory: aprHistory.address,
    },
  });
}
