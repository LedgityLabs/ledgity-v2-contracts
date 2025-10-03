import type { DeployFunction } from "hardhat-deploy/dist/types";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
}) => {
  const { deployer } = await getNamedAccounts();

  await deployments.deploy("GlobalOwner", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
    skipIfAlreadyDeployed: true,
    proxy: {
      proxyContract: "UUPS",
      execute: {
        init: {
          methodName: "initialize",
          args: [],
        },
      },
    },
  });
};

export default deployerFunction;
