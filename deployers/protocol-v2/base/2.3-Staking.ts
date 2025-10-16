import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";
import { getGeneralChainConfig } from "../../../data/configsContracts";

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy StakingPositions".cyan);
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // Retrieve global contracts
  const [globalOwner, globalPause, globalAccessList] = await Promise.all(
    ["GlobalOwner", "GlobalPause", "GlobalAccessList"].map((el) =>
      deployments.get(el).then((el) => el.address as Address),
    ),
  );

  const { stakeToken, maxLockDurationSeconds } = getGeneralChainConfig(
    Number(chainId),
  );

  // Deploy the SafeCastLibrary library first
  console.log("==> Deploy lib SafeCastLibrary".cyan);
  const SafeCastLibraryLib = await deployments.deploy("SafeCastLibrary", {
    from: deployer,
    log: true,
    waitConfirmations: 3,
  });

  // Deploy the BalanceLogicLibrary library first
  console.log("==> Deploy lib BalanceLogicLibrary".cyan);
  const BalanceLogicLibraryLib = await deployments.deploy(
    "BalanceLogicLibrary",
    {
      from: deployer,
      log: true,
      waitConfirmations: 3,
      libraries: {
        SafeCastLibrary: SafeCastLibraryLib.address,
      },
    },
  );

  await deployments.deploy("StakingPositions", {
    from: deployer,
    log: true,
    waitConfirmations: 3,
    skipIfAlreadyDeployed: true,
    libraries: {
      SafeCastLibrary: SafeCastLibraryLib.address,
      BalanceLogicLibrary: BalanceLogicLibraryLib.address,
    },
    proxy: {
      proxyContract: "UUPS",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            stakeToken,
            maxLockDurationSeconds,
            globalOwner,
            globalPause,
            globalAccessList,
          ],
        },
      },
    },
  });
}
