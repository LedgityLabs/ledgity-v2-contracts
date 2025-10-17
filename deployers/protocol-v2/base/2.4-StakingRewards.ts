import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy StakingRewardsDistributor".cyan);
  const { deployer } = await getNamedAccounts();

  // Retrieve global contracts
  const [globalOwner, globalPause, globalAccessList, staking] =
    await Promise.all(
      [
        "GlobalOwner",
        "GlobalPause",
        "GlobalAccessList",
        "StakingPositions",
      ].map((el) => deployments.get(el).then((el) => el.address as Address)),
    );

  const deployed = await deployments.deploy("StakingRewardsDistributor", {
    from: deployer,
    log: true,
    waitConfirmations: 3,
    skipIfAlreadyDeployed: true,
    proxy: {
      proxyContract: "UUPS",
      execute: {
        init: {
          methodName: "initialize",
          args: [staking, globalOwner, globalPause, globalAccessList],
        },
      },
    },
  });

  console.log(
    "-> Deployed StakingRewardsDistributor Proxy address: ".yellow,
    deployed.address,
  );
}
