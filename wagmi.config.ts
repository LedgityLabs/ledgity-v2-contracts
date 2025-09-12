import { defineConfig } from "@wagmi/cli";
import { hardhat, react, actions } from "@wagmi/cli/plugins";
import deployedContracts from "./data/deployments.json";
import { readdirSync, readFileSync } from "fs";
import { join } from "path";

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

/// @dev Contracts whitelist
const contractList = [
  "GlobalBlacklist",
  "GlobalOwner",
  "GlobalPause",
  "LDYStaking",
  "PreMining",
  "LToken",
  "LedgityYieldVault",
  "GenericERC20",
];

// Read ABIs from contracts/abis directory
const abisPath = join(__dirname, "/data/abis");
const abiFiles = readdirSync(abisPath).filter((file) => file.endsWith(".json"));

const contracts: ContractType[] = [];

// First, create contracts from ABI files
for (const abiFile of abiFiles) {
  const contractName = abiFile.replace(".json", "");

  // Skip if not in whitelist
  if (contractList.length && !contractList.includes(contractName)) continue;

  // Exclude chain specific implementations that have same interfaces
  if (contractName.endsWith("Sonic")) continue;
  if (contractName.endsWith("Hedera")) continue;

  try {
    const abiContent = readFileSync(join(abisPath, abiFile), "utf8");
    const abi = JSON.parse(abiContent);

    contracts.push({
      abi,
      address: {},
      name: contractName,
    });
  } catch (error) {
    console.warn(`Failed to read ABI for ${contractName}:`, error);
  }
}

// Then, populate addresses from deployments
for (const chainId in deployedContracts) {
  const contractsData = deployedContracts[chainId][0].contracts;

  if (!contractsData) {
    console.log("No contracts found for chainId: ", chainId);
    continue;
  }

  for (const [name, data] of Object.entries(contractsData)) {
    const chainNumber = Number(chainId);
    const cleanName = name.replace("_Proxy", "");

    // Skip implementation contracts
    if (name.includes("_Implementation")) continue;

    // Find the corresponding contract in our list
    const foundContract = contracts.find(
      (contract: ContractType) => contract.name === cleanName,
    );

    if (foundContract) {
      foundContract.address[chainNumber] = (data as any).address;
    }
  }
}

console.log(
  "\n=> Generating typing for: ",
  JSON.stringify(
    contracts.map((contract) => contract.name),
    null,
    2,
  ),
  "\n",
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
