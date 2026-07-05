import { DeployFunction } from "hardhat-deploy/dist/types";
import {
  Address,
  getContractAddress,
  PublicClient,
  createPublicClient,
  http,
} from "viem";
import { mainnet } from "viem/chains";
import { getGeneralChainConfig } from "../../../data/configsContracts";
import { ethers } from "hardhat";

/// @dev Update the chain depending on the target of deploy script
const network = mainnet;

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
  config,
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
    skipIfAlreadyDeployed: true,
  });

  // Deploy the BalanceLogicLibrary library first
  console.log("==> Deploy lib BalanceLogicLibrary".cyan);
  const BalanceLogicLibraryLib = await deployments.deploy(
    "BalanceLogicLibrary",
    {
      from: deployer,
      log: true,
      waitConfirmations: 3,
      skipIfAlreadyDeployed: true,
      libraries: {
        SafeCastLibrary: SafeCastLibraryLib.address,
      },
    },
  );

  // ===== PRECOMPUTE REWARDS DISTRIBUTOR ADDRESS ===== //

  if (network.id != Number(chainId))
    throw Error("Chain ID mismatch, check configured viem Chain");

  const nonce = await ethers.provider.getTransactionCount(deployer);

  const rewardsDistributorAddress = getContractAddress({
    opcode: "CREATE",
    from: deployer as Address,
    nonce: BigInt(nonce) + 3n,
  });

  console.log(
    "-> Precomputed StakingRewardsDistributor Proxy address: ".yellow,
    rewardsDistributorAddress,
  );

  // ================================================== //

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
            rewardsDistributorAddress,
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
