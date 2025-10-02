import fs from "fs";
import { type DeployFunction } from "hardhat-deploy/dist/types";
import { isAddress, zeroAddress, Address } from "viem";
import { getParametersForVault } from "../../data/configsContracts";

const LTOKEN_SYMBOL = "LEURC";
const VAULT_TOKEN_NAME = "Ledgity EUR Vault";
const VAULT_TOKEN_SYMBOL = "lyEUR";

if (!fs.existsSync("temp/deployedTokens.json"))
  throw new Error("deployedTokens.json not found");

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
  const lTokenAddress = deployedTokens?.[chainId]?.[LTOKEN_SYMBOL];
  const stakeTokenAddress = deployedTokens?.[chainId]?.LDY;
  if (
    !lTokenAddress ||
    lTokenAddress === zeroAddress ||
    !isAddress(lTokenAddress) ||
    !stakeTokenAddress ||
    stakeTokenAddress === zeroAddress ||
    !isAddress(stakeTokenAddress)
  )
    throw new Error(
      `Missing or invalid ${LTOKEN_SYMBOL} or LDY address for chain ${chainId}`,
    );

  const args = getParametersForVault(
    Number(chainId),
    VAULT_TOKEN_NAME,
    VAULT_TOKEN_SYMBOL,
    lTokenAddress,
    stakeTokenAddress,
    globalOwner,
    globalPause,
    globalAccessList,
  );

  // Deploy the LToken
  await deployments.deploy(VAULT_TOKEN_SYMBOL, {
    contract: "LedgityYieldVaultSonic",
    from: deployer,
    log: true,
    proxy: {
      proxyContract: "UUPS",
      implementationName: "LedgityYieldVaultSonic_Implementation",
      execute: {
        init: {
          methodName: "initializeAndRegister",
          args,
        },
      },
    },
    waitConfirmations: 1,
  });
};

export default deployerFunction;
