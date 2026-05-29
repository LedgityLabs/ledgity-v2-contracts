import { defineConfig, type Config } from "@wagmi/cli";
import { hardhat, react, actions } from "@wagmi/cli/plugins";
import deployedContracts from "./data/deployments.json";

/// @dev Contracts whitelist
const contractList = [
  // v1
  "GlobalBlacklist",
  "GlobalOwner",
  "GlobalPause",
  "LDYStaking",
  "LTokenSignaler",
  "PreMining",
  "LToken",
  // v2
  "GlobalAccessList",
  "LedgityYieldVault",
  "GenericERC20",
  "StakingPositions",
  "StakingRewardsDistributor",
  "CouncilMerkleDistributor",
  "LedgityYieldVaultSonic",
  "StakingPositionsSonic",
  "StakingRewardsDistributorSonic",
  "KrystalYieldVault",
  "LegacyStakingTransition",
  "FixedTermInvestmentVault",
];

type ContractMap = {
  [name: string]: {
    abi: any;
    address: { [chainId: number]: `0x${string}` };
  };
};

console.log(
  "\n=> Generating typing for: ",
  JSON.stringify(contractList, null, 2),
  "\n",
);

const contractMap: ContractMap = {};

for (const chainId in deployedContracts) {
  const contractsData = (deployedContracts as any)[chainId][0]?.contracts;
  if (!contractsData) continue;

  for (const [name, data] of Object.entries(contractsData)) {
    const cleanName = name.replace("_Proxy", "");
    if (!contractList.includes(cleanName)) continue;

    const chainNumber = Number(chainId);
    if (!contractMap[cleanName]) {
      contractMap[cleanName] = { abi: (data as any).abi, address: {} };
    }
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
