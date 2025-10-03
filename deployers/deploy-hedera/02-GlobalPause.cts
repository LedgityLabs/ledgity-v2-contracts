import type { DeployFunction } from "hardhat-deploy/dist/types";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
}) => {
  const { deployer } = await getNamedAccounts();

  const globalOwner = await deployments.get("GlobalOwner");

  await deployments.deploy("GlobalPause", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    skipIfAlreadyDeployed: true,
    proxy: {
      proxyContract: "UUPS",
      execute: {
        init: {
          methodName: "initialize",
          args: [globalOwner.address],
        },
      },
    },
  });
};

export default deployerFunction;
