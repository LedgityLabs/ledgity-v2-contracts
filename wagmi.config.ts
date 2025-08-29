import { defineConfig } from "@wagmi/cli";
import { hardhat, react, actions } from "@wagmi/cli/plugins";
import deployments from "./data/deployments.json";

// Converts deployments data into format awaited by the hardhat plugin
// See: https://wagmi.sh/cli/plugins/hardhat#deployments-optional
// Generic contracts are implementation for proxies
const genericContracts = [
  "WrappedLToken",
  "WrappedLTokenSonic",
  "WrappedLTokenHedera",
  "LToken",
  "LTokenSonic",
  "LTokenHedera",
];
let hhPluginDeployments = {};
for (let chainId in deployments) {
  let contractList =
    deployments[chainId as keyof typeof deployments][0].contracts;
  for (const [contractName, contractData] of Object.entries(contractList)) {
    // Exclude implementation and proxy contracts
    if (
      genericContracts.includes(contractName) ||
      contractName.includes("_Implementation") ||
      contractName.includes("_Proxy")
    )
      continue;

    if (!hhPluginDeployments[contractName])
      hhPluginDeployments[contractName] = {};
    hhPluginDeployments[contractName][chainId] = contractData.address;
  }
}

export default defineConfig({
  out: "src/types/contractTypes.ts",
  plugins: [
    hardhat({
      project: "./",
      deployments: hhPluginDeployments,
      include: ["src/"],
      exclude: ["src/protocol-v1/abstracts/**", "src/protocol-v1/libs/**"],
    }),
    react(),
    actions(),
  ],
});
