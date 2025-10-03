import { type DeployFunction } from "hardhat-deploy/dist/types";
import { writeTempTokenAddress } from "../../data/configsContracts";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
  getChainId,
}) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  const result = await deployments.deploy("LDY", {
    from: deployer,
    contract: "LDY",
    log: true,
    waitConfirmations: 1,
    skipIfAlreadyDeployed: true,
  });

  // Update deployedTokens.json
  writeTempTokenAddress(chainId, "LDY", result.address);
};

export default deployerFunction;
