import fs from "fs";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { ethers } from "hardhat";

const LTOKEN_SYMBOLS = ["LUSDC"];

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  const globalOwner = await deployments.get("GlobalOwner");

  const result = await deployments.deploy("LTokenSignaler", {
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

  // Skip signaling tokens if this is the previous deployment
  if (!result.newlyDeployed) return;

  if (!fs.existsSync("temp/deployedTokens.json")) return;

  const deployedTokens: {
    [chainId: string]: {
      [symbol: string]: string;
    };
  } = JSON.parse(fs.readFileSync("temp/deployedTokens.json", "utf8"));

  const lTokenSignaler = await ethers.getContractAt(
    "LTokenSignaler",
    result.address,
  );

  for (const symbol of LTOKEN_SYMBOLS) {
    const lTokenAddress = deployedTokens?.[chainId]?.[symbol];
    if (!lTokenAddress) continue;

    await lTokenSignaler
      .signalLToken(lTokenAddress)
      .then((tx: any) => tx.wait(1));

    console.log(`=> LToken ${symbol} signaled`);
  }
}
