import { DeployFunction } from "hardhat-deploy/dist/types";
import { writeTempTokenAddress } from "../../data/configsContracts";

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
}: Parameters<DeployFunction>[0]) {
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
}
