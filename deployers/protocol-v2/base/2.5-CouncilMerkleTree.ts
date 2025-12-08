import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";
import { getGeneralChainConfig } from "../../../data/configsContracts";

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy CouncilMerkleDistributor".cyan);
  console.log("CouncilMerkleDistributor deployement disabled for now".yellow);
  return; // @dev Disabled for now

  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // Retrieve global contracts
  const [globalOwner, globalPause, globalAccessList] = await Promise.all(
    ["GlobalOwner", "GlobalPause", "GlobalAccessList"].map((el) =>
      deployments.get(el).then((el) => el.address as Address),
    ),
  );

  const { stakeToken, initialMerkleRoot } = getGeneralChainConfig(
    Number(chainId),
  );

  await deployments.deploy("CouncilMerkleDistributor", {
    from: deployer,
    log: true,
    waitConfirmations: 3,
    skipIfAlreadyDeployed: true,
    proxy: {
      proxyContract: "UUPS",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            stakeToken,
            initialMerkleRoot,
            globalOwner,
            globalPause,
            globalAccessList,
          ],
        },
      },
    },
  });
}
