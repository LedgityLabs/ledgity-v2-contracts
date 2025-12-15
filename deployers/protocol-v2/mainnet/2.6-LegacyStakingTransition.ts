import { DeployFunction } from "hardhat-deploy/dist/types";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy LegacyStakingTransition".cyan);
  const { deployer } = await getNamedAccounts();

  const deployed = await deployments.deploy("LegacyStakingTransition", {
    from: deployer,
    log: true,
    waitConfirmations: 2,
    skipIfAlreadyDeployed: true,
  });

  console.log(
    "-> Deployed LegacyStakingTransition address: ".yellow,
    deployed.address,
  );
}
