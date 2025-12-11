import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";

export default async function deploy({
  getNamedAccounts,
  deployments,
}: Parameters<DeployFunction>[0]) {
  console.log("\n=> Deploy KrystalYieldVault".cyan);
  const { deployer } = await getNamedAccounts();

  // Retrieve global contracts
  const [globalOwner, globalPause, globalAccessList] = await Promise.all(
    ["GlobalOwner", "GlobalPause", "GlobalAccessList"].map((el) =>
      deployments.get(el).then((el) => el.address as Address),
    ),
  );

  const deployed = await deployments.deploy("KrystalYieldVault", {
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
            "0x2f59E0aa5fCe7898620f65621Ab0f8E2bD308448", // address krystalVault_
            "LP strategy", // string calldata name_
            "LPS", // string calldata symbol_
            globalOwner, // address globalOwner_
            globalPause, // address globalPause_
            globalAccessList, // address globalRestrict_
            100, // uint256 slippageTolerance_
          ],
        },
      },
    },
  });

  console.log(
    "-> Deployed KrystalYieldVault Proxy address: ".yellow,
    deployed.address,
  );
}
