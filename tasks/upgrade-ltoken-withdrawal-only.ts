import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";

/**
 * Prepares the withdrawal-only upgrade of the legacy v1 LTokens on the connected chain:
 *   1. deploys the new LToken implementation (LTokenSonic on Sonic) from the deployer,
 *   2. resolves the legacy LTokens from the live v2 vaults (`lToken()`),
 *   3. writes a Safe Transaction Builder batch with, for each legacy LToken,
 *      `upgradeTo(newImplementation)` followed by `switchWithdrawalOnly(true)`.
 *
 * Nothing is changed on the proxies by this task: their owner is the Safe, which
 * executes the batch from data/safe/<network>-ltoken-withdrawal-only.json.
 *
 * Usage: `npm run upgrade-ltoken:<chain>` (live) or `npm run upgrade-ltoken-fork:<chain>`
 * (rehearsal on a hardhat fork, the batch is written all the same).
 */

/// @dev v2 vault proxies whose lToken() is a legacy v1 LToken, per chain id
const VAULTS_BY_CHAIN: Record<number, { symbol: string; address: string }[]> = {
  8453: [
    { symbol: "lyUSD", address: "0x916f179D5D9B7d8Ad815AC2f8570aabF0C6a6e38" },
    { symbol: "lyEUR", address: "0xFaA1e3720e6Ef8cC76A800DB7B3dF8944833b134" },
  ],
  42161: [
    { symbol: "lyUSD", address: "0x283F35b6406a0e19a786ed119869eF2c0fE157Ee" },
  ],
  59144: [
    { symbol: "lyUSD", address: "0x43b3c64dbc95F9eD83795E051fc00014059e698F" },
  ],
  146: [
    { symbol: "lyUSD", address: "0x65f75c675Cc76474662DfBF7B6e8683764223001" },
  ],
};

const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const VAULT_ABI = ["function lToken() view returns (address)"];
const LTOKEN_ABI = [
  "function owner() view returns (address)",
  "function symbol() view returns (string)",
  "function upgradeTo(address newImplementation)",
  "function switchWithdrawalOnly(bool status_)",
];

task(
  "upgrade-ltoken-withdrawal-only",
  "Deploys the withdrawal-only LToken implementation and writes the Safe batch upgrading the legacy LTokens",
).setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers, network } = hre;
  const { deployer } = await getNamedAccounts();
  const chainId = Number(await hre.getChainId());
  const isFork = network.name === "hardhat";
  const forkName = process.env.HARDHAT_DEPLOY_FORK?.toLowerCase();
  const label = isFork ? `${forkName}-fork` : network.name;

  const vaults = VAULTS_BY_CHAIN[chainId];
  if (!vaults) throw Error(`No legacy LToken to upgrade on chain ${chainId}`);

  console.log(
    `\n=> Upgrade legacy LTokens to withdrawal only on ${label}`.cyan,
  );
  console.log("==> Deployer".cyan, deployer);

  // A custom task does not compile by itself: without this the stale artifacts get deployed
  await hre.run("compile");

  // 1. New implementation, linked to the APRHistory library like the original deployment
  const isSonic = chainId === 146;
  let aprHistoryAddress: string;
  try {
    aprHistoryAddress = (await deployments.get("APRHistory")).address;
  } catch {
    console.log(
      "==> No APRHistory record on this network, deploying it".yellow,
    );
    aprHistoryAddress = (
      await deployments.deploy("APRHistory", { from: deployer, log: true })
    ).address;
  }

  const implementation = await deployments.deploy(
    isSonic ? "LTokenSonic_Implementation" : "LToken_Implementation",
    {
      contract: isSonic ? "LTokenSonic" : "LToken",
      from: deployer,
      log: true,
      waitConfirmations: isFork ? 1 : 3,
      libraries: { APRHistory: aprHistoryAddress },
    },
  );
  console.log("==> New implementation".cyan, implementation.address);

  // Never write a batch towards an implementation without the withdrawal-only switch
  const deployedCode = await ethers.provider.getCode(implementation.address);
  const switchSelector = new ethers.utils.Interface(LTOKEN_ABI)
    .getSighash("switchWithdrawalOnly")
    .slice(2);
  if (!deployedCode.includes(`63${switchSelector}`))
    throw Error(
      `${implementation.address} has no switchWithdrawalOnly(bool): stale artifact deployed, nothing written`,
    );

  // 2. Legacy LTokens, read from the live vaults, and their Safe owner
  const lTokenInterface = new ethers.utils.Interface(LTOKEN_ABI);
  const transactions: {
    to: string;
    value: string;
    data: string;
    contractMethod: null;
    contractInputsValues: null;
  }[] = [];
  const owners = new Set<string>();

  for (const vault of vaults) {
    const lTokenAddress: string = await (
      await ethers.getContractAt(VAULT_ABI, vault.address)
    ).lToken();
    if (lTokenAddress === ethers.constants.AddressZero) {
      console.log(`==> ${vault.symbol}: no lToken set, skipped`.yellow);
      continue;
    }

    const lToken = await ethers.getContractAt(LTOKEN_ABI, lTokenAddress);
    const [symbol, owner, currentImplementation] = await Promise.all([
      lToken.symbol(),
      lToken.owner(),
      ethers.provider.getStorageAt(lTokenAddress, IMPLEMENTATION_SLOT),
    ]);
    owners.add(owner);

    console.log(
      `==> ${vault.symbol} <- ${symbol}`.cyan,
      lTokenAddress,
      `\n    owner ${owner}\n    implementation ${ethers.utils.getAddress("0x" + currentImplementation.slice(26))} -> ${implementation.address}`,
    );

    // 3. The two Safe transactions for this LToken
    transactions.push(
      {
        to: lTokenAddress,
        value: "0",
        data: lTokenInterface.encodeFunctionData("upgradeTo", [
          implementation.address,
        ]),
        contractMethod: null,
        contractInputsValues: null,
      },
      {
        to: lTokenAddress,
        value: "0",
        data: lTokenInterface.encodeFunctionData("switchWithdrawalOnly", [
          true,
        ]),
        contractMethod: null,
        contractInputsValues: null,
      },
    );
  }

  if (owners.size !== 1)
    throw Error(
      `Expected a single Safe owning every legacy LToken, got: ${[...owners].join(", ")}`,
    );
  const [safe] = [...owners];

  const batch = {
    version: "1.0",
    chainId: chainId.toString(),
    createdAt: Date.now(),
    meta: {
      name: `Legacy LTokens: withdrawal only (${label})`,
      description:
        "Upgrade each legacy v1 LToken to the withdrawal-only implementation, then close deposits. Withdrawals, transfers and the migration to the v2 vaults stay open.",
      txBuilderVersion: "1.16.5",
      createdFromSafeAddress: safe,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions,
  };

  const outDir = path.join(__dirname, "..", "data", "safe");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `${label}-ltoken-withdrawal-only.json`);
  fs.writeFileSync(outFile, JSON.stringify(batch, null, 2) + "\n", "utf8");

  console.log(
    `\n==> Safe batch (${transactions.length} transactions) written to`.green,
    path.relative(process.cwd(), outFile),
  );
  console.log(
    `==> Push it to the admin page: cd ../ledgity-api && npx tsx scripts/proposeMultisigBundle.ts ${path.relative(path.join(process.cwd(), "..", "ledgity-api"), outFile)}`
      .green,
  );
  console.log(
    `==> (or import it in the Safe Transaction Builder from ${safe}), then run npm run verify:${isFork ? forkName : network.name} for the implementation`
      .green,
  );
});
