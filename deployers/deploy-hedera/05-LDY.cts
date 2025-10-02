import fs from "fs";
import { type DeployFunction } from "hardhat-deploy/dist/types";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
  getChainId,
}) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!fs.existsSync("temp/deployedTokens.json")) {
    fs.mkdirSync("temp");
    fs.writeFileSync("temp/deployedTokens.json", "{}", "utf8");
  }

  const result = await deployments.deploy("LDY", {
    from: deployer,
    contract: "LDY",
    log: true,
    waitConfirmations: 1,
  });

  // Update deployedTokens.json
  const deployedTokens: {
    [chainId: string]: {
      [symbol: string]: string;
    };
  } = JSON.parse(fs.readFileSync("temp/deployedTokens.json", "utf8"));

  deployedTokens[chainId] ??= {};
  deployedTokens[chainId]["LDY"] = result.address;

  fs.writeFileSync(
    "temp/deployedTokens.json",
    JSON.stringify(deployedTokens, null, 2),
    "utf8",
  );
};

export default deployerFunction;
