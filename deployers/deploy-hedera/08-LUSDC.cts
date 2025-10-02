import type { DeployFunction } from "hardhat-deploy/dist/types";
import {
  getTokenAddress,
  writeTempTokenAddress,
} from "../../data/configsContracts";

const LTOKEN_NAME = "Ledgity USDC";
const LTOKEN_SYMBOL = "LUSDC";
const UNDERLYING_TOKEN_SYMBOL = "USDC";
const IS_HTOKEN = true;

const deployerFunction: DeployFunction = async ({
  getNamedAccounts,
  deployments,
  getChainId,
}) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  // Retrieve global contracts
  const globalOwner = await deployments.get("GlobalOwner");
  const globalPause = await deployments.get("GlobalPause");
  const globalBlacklist = await deployments.get("GlobalBlacklist");
  const ldyStaking = await deployments.get("LDYStaking");
  const aprHistory = await deployments.get("APRHistory");

  // Check if the underlying token is set in dependencies
  const UNDERLYING_TOKEN = getTokenAddress(chainId, UNDERLYING_TOKEN_SYMBOL);

  // Deploy the proxy
  const result = await deployments.deploy(LTOKEN_SYMBOL, {
    contract: "LTokenHedera",
    from: deployer,
    log: true,
    libraries: {
      APRHistory: aprHistory.address,
    },
    proxy: {
      proxyContract: "UUPS",
      implementationName: "LTokenHedera_Implementation",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            globalOwner.address,
            globalPause.address,
            globalBlacklist.address,
            ldyStaking.address,
            UNDERLYING_TOKEN,
            IS_HTOKEN,
            LTOKEN_NAME,
            LTOKEN_SYMBOL,
          ],
        },
      },
    },
    waitConfirmations: 1,
  });

  // Update deployedTokens.json
  writeTempTokenAddress(chainId, LTOKEN_SYMBOL, result.address);
};

export default deployerFunction;
