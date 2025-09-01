import { defineConfig } from "@wagmi/cli";
import { hardhat, react, actions } from "@wagmi/cli/plugins";
import deployedContracts from "./data/deployments.json";

type ContractType = {
  abi: any;
  address: {
    [chainId: number]: `0x${string}`;
  };
  name: string;
};

type DeploymentsType = {
  [name: string]: {
    [chainId: number]: `0x${string}`;
  };
};

/// @dev Implementation contracts or libraries we want to avoid
const filterList = [
  "APRHistory",
  "Multicall3",
  "USDC",
  "WrappedLToken",
  "LTokenSignaler",
];
const contracts: ContractType[] = [];

for (const chainId in deployedContracts) {
  const contractsData = deployedContracts[chainId][0].contracts;

  if (!contractsData) {
    console.log("No contracts found for chainId: ", chainId);
    continue;
  }

  for (const [name, data] of Object.entries(contractsData)) {
    const chainNumber = Number(chainId);
    const cleanName = name.replace("_Proxy", "");

    if (filterList.includes(cleanName)) continue;
    // Exclude implementation
    if (name.includes("_Implementation")) continue;
    // Exclude chain specific implementation that have same interfaces
    if (cleanName.endsWith("Sonic")) continue;
    if (cleanName.endsWith("Hedera")) continue;

    const foundItem = contracts.find(
      (item: ContractType) => item.name === cleanName,
    );

    if (foundItem) {
      foundItem.address[chainNumber] = (data as any).address;
    } else {
      contracts.push({
        abi: (data as any).abi,
        address: {
          [chainNumber]: (data as any).address,
        },
        name: cleanName,
      });
    }
  }
}

console.log(
  "=> Generating typing for: ",
  JSON.stringify(
    contracts.map((contract) => contract.name),
    null,
    2,
  ),
);

const deployments: DeploymentsType = contracts.reduce((acc, contract) => {
  acc[contract.name] = contract.address;
  return acc;
}, {} as DeploymentsType);

export default defineConfig({
  out: "types/contractTypes.ts",
  contracts,
  plugins: [
    hardhat({
      project: "../ledgity-v2-contracts/",
      deployments,
      include: ["src/protocol-v2/"],
      exclude: ["src/protocol-v1/abstracts/**", "src/protocol-v1/libs/**"],
    }),
    react(),
    actions(),
  ],
});
