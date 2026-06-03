import { defineConfig, type Config } from "@wagmi/cli";
import { hardhat, react, actions } from "@wagmi/cli/plugins";
import deployedContracts from "./data/deployments.json";
// Abis
import GenericERC20Abi from "./data/abis/GenericERC20.json";

/// @dev Contracts whitelist
const contractList = [
  // v1
  "GlobalBlacklist",
  "GlobalOwner",
  "GlobalPause",
  "LDYStaking",
  "LTokenSignaler",
  "PreMining",
  // v2
  "GlobalAccessList",
  "StakingPositions",
  "StakingRewardsDistributor",
  "CouncilMerkleDistributor",
  "StakingPositionsSonic",
  "StakingRewardsDistributorSonic",
  "KrystalYieldVault",
  "LegacyStakingTransition",
  // implementations
  "LToken_Implementation",
  "LedgityYieldVault_Implementation",
  "LedgityYieldVaultSonic_Implementation",
  "FixedTermInvestmentVault_Implementation",
];

console.log(
  "\n=> Generating typing for: ",
  JSON.stringify(contractList, null, 2),
  "\n",
);

const contractMap: {
  [name: string]: {
    abi: any;
    address: { [chainId: number]: `0x${string}` };
  };
} = {
  GenericERC20: {
    abi: GenericERC20Abi,
    address: {},
  },
};

for (const chainId in deployedContracts) {
  const contractsData = (deployedContracts as any)[chainId][0]?.contracts;
  if (!contractsData) continue;

  for (const [name, data] of Object.entries(contractsData)) {
    const baseContractName = name.replace("_Proxy", "").replace("Sonic", "");
    if (!contractList.includes(baseContractName)) continue;

    // Normalize Sonic & implementation contracts
    const cleanName = name
      .replace("_Implementation", "")
      .replace("_Proxy", "")
      .replace("Sonic", "");
    const chainNumber = Number(chainId);
    if (!contractMap[cleanName]) {
      contractMap[cleanName] = { abi: (data as any).abi, address: {} };
    }

    // Skip implementation addresses as we use proxy for calls
    if (name.includes("_Implementation")) continue;

    contractMap[cleanName].address[chainNumber] = (data as any).address;
  }
}

const contracts = Object.entries(contractMap).map(
  ([name, { abi, address }]) => ({
    name,
    abi,
    address: Object.keys(address).length > 0 ? address : undefined,
  }),
);

console.log(
  "deployments:\n",
  JSON.stringify(
    contracts.reduce(
      (acc, contract) => {
        if (contract.address) acc[contract.name] = contract.address;
        return acc;
      },
      {} as {
        [name: string]: {
          [chainId: number]: `0x${string}`;
        };
      },
    ),
    null,
    2,
  ),
);

export default defineConfig({
  out: "types/contractTypes.ts",
  contracts,
  plugins: [
    hardhat({
      project: "../ledgity-v2-contracts/",
      include: ["src/"],
    }),
    react(),
    actions(),
  ],
}) as Config;
