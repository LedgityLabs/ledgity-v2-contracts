import type { DeployFunction } from "hardhat-deploy/dist/types";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
}) => {
  const { deployer } = await getNamedAccounts();

  // Deploy the shared implementation
  await deployments.deploy("LedgityYieldVaultHedera", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  });
};

export default deployerFunction;
