import { DeployFunction } from "hardhat-deploy/dist/types";
import { Address } from "viem";
import {
  getParametersForVault,
  writeTempTokenAddress,
} from "../../../data/configsContracts";

const VAULT_TOKEN_NAME = "Ledgity USD Vault";
const VAULT_TOKEN_SYMBOL = "lyUSD";

export default async function deploy({
  getNamedAccounts,
  deployments,
  getChainId,
}: Parameters<DeployFunction>[0]) {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // Retrieve global contracts
  const [globalOwner, globalPause, globalAccessList, ledgityDataProviderLib] =
    await Promise.all(
      [
        "GlobalOwner",
        "GlobalPause",
        "GlobalAccessList",
        "LedgityDataProvider",
      ].map((el) => deployments.get(el).then((el) => el.address as Address)),
    );

  const args = getParametersForVault(
    Number(chainId),
    VAULT_TOKEN_NAME,
    VAULT_TOKEN_SYMBOL,
    globalOwner,
    globalPause,
    globalAccessList,
  );

  // Deploy the LToken
  console.log(`\n=> Deploy ${VAULT_TOKEN_SYMBOL}`.cyan);
  const result = await deployments.deploy(VAULT_TOKEN_SYMBOL, {
    contract: "LedgityYieldVault",
    from: deployer,
    log: true,
    waitConfirmations: 3,
    libraries: {
      LedgityDataProvider: ledgityDataProviderLib,
    },
    proxy: {
      proxyContract: "UUPS",
      implementationName: "LedgityYieldVault_Implementation",
      execute: {
        init: {
          methodName: "initialize",
          args,
        },
      },
    },
  });

  // Update deployedTokens.json
  writeTempTokenAddress(chainId, VAULT_TOKEN_SYMBOL, result.address);
}
