import fs from "fs";
import { type DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";
import {
  getParametersForVault,
  getTokenAddress,
  writeTempTokenAddress,
} from "../../data/configsContracts";

const LTOKEN_SYMBOL = "LUSDC";
const VAULT_TOKEN_NAME = "Ledgity USD Vault";
const VAULT_TOKEN_SYMBOL = "lyUSD";

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
  getChainId,
}) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // Retrieve global contracts
  const globalOwner = await deployments
    .get("GlobalOwner")
    .then((d) => d.address as Address);
  const globalPause = await deployments
    .get("GlobalPause")
    .then((d) => d.address as Address);
  const globalAccessList = await deployments
    .get("GlobalAccessList")
    .then((d) => d.address as Address);

  const deployedTokens: {
    [chainId: string]: {
      [symbol: string]: string;
    };
  } = JSON.parse(fs.readFileSync("temp/deployedTokens.json", "utf8"));

  // Check if the underlying lToken is set in dependencies
  const LTOKEN_ADDRESS = getTokenAddress(chainId, LTOKEN_SYMBOL);
  const LDY_ADDRESS = getTokenAddress(chainId, "LDY");

  const args = getParametersForVault(
    Number(chainId),
    VAULT_TOKEN_NAME,
    VAULT_TOKEN_SYMBOL,
    LTOKEN_ADDRESS,
    LDY_ADDRESS,
    globalOwner,
    globalPause,
    globalAccessList,
  );

  // Deploy the LToken
  const result = await deployments.deploy(VAULT_TOKEN_SYMBOL, {
    contract: "LedgityYieldVaultHedera",
    from: deployer,
    log: true,
    waitConfirmations: 1,
    deterministicDeployment: true,
    proxy: {
      proxyContract: "UUPS",
      implementationName: "LedgityYieldVaultHedera_Implementation",
      execute: {
        init: {
          methodName: "initializeAndRegister",
          args,
        },
      },
    },
  });

  // Update deployedTokens.json
  writeTempTokenAddress(chainId, VAULT_TOKEN_SYMBOL, result.address);
};

export default deployerFunction;
