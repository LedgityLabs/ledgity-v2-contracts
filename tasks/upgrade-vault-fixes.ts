import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";

/**
 * Prepares the maintenance upgrade of the live vault proxies (lyUSD, lyEUR, lyREI) on the
 * connected chain:
 *   1. deploys LedgityDataProvider (the withdrawal request views, read from the vaults) and
 *      the vault implementations from the deployer,
 *   2. checks the new bytecode carries the fixes, no longer has the moved views, and that the
 *      targets are vault proxies owned by one Safe,
 *   3. writes a Safe Transaction Builder batch: for each vault, upgradeTo(), then
 *      updateHighWaterMark() with the live price per share: the mark sat at 1e18 (an artefact
 *      of the empty-vault price at initialization) where the real price of a 6-decimal vault
 *      is about 1.1e6, so the performance fee could never apply. The first harvest after the
 *      execution moves the mark to the exact price of that block (the rate is 0: no fee is
 *      taken by that move).
 *
 * The withdrawal fee alignment (0.3 % and the 50k veLDY reduction on every vault) is left for
 * the V3 launch (Pierre-Yves, 2026-11-05): no updateVaultParams() in this batch.
 *
 * Nothing is changed on the proxies by this task: their owner is the Safe, which executes
 * the batch from data/safe/<network>-vault-fixes.json.
 *
 * Usage: `npm run upgrade-vaults:<chain>` (live) or `npm run upgrade-vaults-fork:<chain>`
 * (rehearsal on a hardhat fork, the batch is written all the same).
 */

type Vault = { label: string; proxy: string; contract: string };

/// @dev Live vault proxies, per chain id
const VAULTS_BY_CHAIN: Record<number, Vault[]> = {
  1: [
    {
      label: "lyUSD",
      proxy: "0x3C769d0e8D21d380228dFB7918c6933bb6ecB6D4",
      contract: "LedgityYieldVault",
    },
    {
      label: "lyEUR",
      proxy: "0x20968165B7d2cDF33aF632aAB3e0539848d44BC8",
      contract: "LedgityYieldVault",
    },
  ],
  8453: [
    {
      label: "lyUSD",
      proxy: "0x916f179D5D9B7d8Ad815AC2f8570aabF0C6a6e38",
      contract: "LedgityYieldVault",
    },
    {
      label: "lyEUR",
      proxy: "0xFaA1e3720e6Ef8cC76A800DB7B3dF8944833b134",
      contract: "LedgityYieldVault",
    },
    {
      label: "lyREI",
      proxy: "0x085b292A7c54767d5371fE939a4Ad4dC9828d98f",
      contract: "FixedTermInvestmentVault",
    },
  ],
  42161: [
    {
      label: "lyUSD",
      proxy: "0x283F35b6406a0e19a786ed119869eF2c0fE157Ee",
      contract: "LedgityYieldVault",
    },
  ],
  59144: [
    {
      label: "lyUSD",
      proxy: "0x43b3c64dbc95F9eD83795E051fc00014059e698F",
      contract: "LedgityYieldVault",
    },
  ],
  146: [
    {
      label: "lyUSD",
      proxy: "0x65f75c675Cc76474662DfBF7B6e8683764223001",
      contract: "LedgityYieldVaultSonic",
    },
  ],
};

const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const VAULT_ABI = [
  "function owner() view returns (address)",
  "function highWaterMark() view returns (uint256)",
  "function getFeeData() view returns (uint256 feeShares, uint256 pricePerShare)",
  "function upgradeTo(address newImplementation)",
  "function updateHighWaterMark(uint256 newHighWaterMark)",
];

/// @dev Functions a vault proxy and the new implementations must have, and one they must not
const VAULT_SELECTOR = "function requestWithdrawal(uint256)";
const MARK_SELECTOR = "function updateHighWaterMark(uint256)";
const MOVED_VIEW_SELECTOR = "function getWithdrawalRequests(bool,uint256)";

/// @dev Text only the fixed sources contain, checked in the compiled source of the deployed artifact
const FIX_MARKERS: Record<string, string[]> = {
  "src/protocol-v2/modules/VaultLiquidityModule.sol": [
    "Start newly-enabled management fees from now",
    "shares = 10 ** decimalsOffset",
    "high-water mark can only be crossed by a real gain",
  ],
  "src/protocol-v2/LedgityYieldVault.sol": [
    "Mark each request processed here to catch duplicate IDs",
    "revert IncompatibleLendingPool()",
    "Without a buffer strategy the added liquidity is already in the asset balance",
    "stakeToken.balanceOf(owner_) < stakeForInstantWithdrawal",
  ],
  "src/protocol-v2/FixedTermInvestmentVault.sol": [
    "Mark each request processed here to catch duplicate IDs",
    "revert IncompatibleLendingPool()",
    "Without a buffer strategy the added liquidity is already in the asset balance",
    "stakeToken.balanceOf(owner_) < stakeForInstantWithdrawal",
    "No legacy L-Token maps to a fixed-term vault",
  ],
};

task(
  "upgrade-vault-fixes",
  "Deploys LedgityDataProvider and the fixed vault implementations, and writes the Safe batch upgrading the vaults",
).setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers, network } = hre;
  const { deployer } = await getNamedAccounts();
  const chainId = Number(await hre.getChainId());
  const isFork = network.name === "hardhat";
  const forkName = process.env.HARDHAT_DEPLOY_FORK?.toLowerCase();
  const label = isFork ? `${forkName}-fork` : network.name;

  const vaults = VAULTS_BY_CHAIN[chainId];
  if (!vaults) throw Error(`No vault to upgrade on chain ${chainId}`);

  console.log(`\n=> Upgrade the vaults on ${label}`.cyan);
  console.log("==> Deployer".cyan, deployer);

  // A custom task does not compile by itself: without this the stale artifacts get deployed
  await hre.run("compile");

  // Optional fee cap (gwei): the node refuses the transaction up front instead of overpaying,
  // e.g. DEPLOY_MAX_FEE_GWEI=0.08 DEPLOY_PRIORITY_FEE_GWEI=0.04 on Linea, where the default
  // maximum fee is priced at 1 gwei for a 0.04 gwei effective price
  const feeCap = process.env.DEPLOY_MAX_FEE_GWEI
    ? {
        maxFeePerGas: ethers.utils
          .parseUnits(process.env.DEPLOY_MAX_FEE_GWEI, "gwei")
          .toString(),
        maxPriorityFeePerGas: ethers.utils
          .parseUnits(process.env.DEPLOY_PRIORITY_FEE_GWEI ?? "0.01", "gwei")
          .toString(),
      }
    : {};
  if (process.env.DEPLOY_MAX_FEE_GWEI)
    console.log(
      `==> Fee cap ${process.env.DEPLOY_MAX_FEE_GWEI} gwei (priority ${process.env.DEPLOY_PRIORITY_FEE_GWEI ?? "0.01"})`
        .yellow,
    );

  // A function selector pushed by the dispatcher (PUSH4 <selector>)
  const has = (code: string, signature: string) => {
    const selector = new ethers.utils.Interface([signature])
      .getSighash(signature.split(" ")[1].split("(")[0])
      .slice(2);
    return code.toLowerCase().includes(`63${selector}`);
  };
  // The deployed bytecode is the artifact just compiled, and that artifact holds the fixes
  const assertFixDeployed = async (
    address: string,
    deployedBytecode: string | undefined,
    contractFqn: string,
  ) => {
    const buildInfo = await hre.artifacts.getBuildInfo(contractFqn);
    const [file, name] = contractFqn.split(":");
    // Immutables (UUPSUpgradeable's own address) are written at deploy time: blank them
    const immutableReferences: Record<
      string,
      { start: number; length: number }[]
    > =
      buildInfo?.output.contracts[file]?.[name]?.evm.deployedBytecode
        .immutableReferences ?? {};
    let onChain = (await ethers.provider.getCode(address)).toLowerCase();
    for (const references of Object.values(immutableReferences))
      for (const { start, length } of references)
        onChain =
          onChain.slice(0, 2 + start * 2) +
          "0".repeat(length * 2) +
          onChain.slice(2 + (start + length) * 2);
    if (!deployedBytecode || onChain !== deployedBytecode.toLowerCase())
      throw Error(
        `${address} does not hold the compiled ${contractFqn}: nothing written`,
      );
    for (const [sourceFile, markers] of Object.entries(FIX_MARKERS)) {
      const source = buildInfo?.input.sources[sourceFile]?.content;
      // The yield vault build does not include the fixed-term source and vice versa
      if (source === undefined) continue;
      for (const marker of markers)
        if (!source.includes(marker))
          throw Error(
            `${contractFqn} was compiled without the fix (${sourceFile} lacks "${marker}"): nothing written`,
          );
    }
    if (!has(onChain, VAULT_SELECTOR) || !has(onChain, MARK_SELECTOR))
      throw Error(`${address} is not a vault implementation`);
    if (has(onChain, MOVED_VIEW_SELECTOR))
      throw Error(`${address} still carries the views moved to LedgityDataProvider`);
  };
  const implementationOf = async (proxy: string) =>
    ethers.utils.getAddress(
      "0x" +
        (await ethers.provider.getStorageAt(proxy, IMPLEMENTATION_SLOT)).slice(
          26,
        ),
    );

  // 1. Targets: vault proxies running a vault today, all owned by the same Safe
  let safe: string | undefined;
  const live: Record<
    string,
    { current: string; highWaterMark: string; pricePerShare: string }
  > = {};
  for (const vault of vaults) {
    const proxy = await ethers.getContractAt(VAULT_ABI, vault.proxy);
    const current = await implementationOf(vault.proxy);
    if (!has(await ethers.provider.getCode(current), VAULT_SELECTOR))
      throw Error(`${vault.label} ${vault.proxy} does not run a vault`);
    const owner: string = await proxy.owner();
    if (safe && owner !== safe)
      throw Error(`Owners differ: ${safe} / ${owner} (${vault.label})`);
    safe = owner;
    live[vault.label] = {
      current,
      highWaterMark: (await proxy.highWaterMark()).toString(),
      pricePerShare: (await proxy.getFeeData()).pricePerShare.toString(),
    };
  }
  if (!safe) throw Error("No vault");

  // 2. LedgityDataProvider and the new implementations
  const dataProvider = await deployments.deploy("LedgityDataProvider", {
    contract: "LedgityDataProvider",
    from: deployer,
    log: true,
    waitConfirmations: isFork ? 1 : 3,
    ...feeCap,
  });
  if (
    !has(
      await ethers.provider.getCode(dataProvider.address),
      "function getWithdrawalRequests(address,bool,uint256)",
    )
  )
    throw Error(`${dataProvider.address} is not the LedgityDataProvider contract`);

  const implementations: Record<string, string> = {};
  for (const contract of [...new Set(vaults.map((v) => v.contract))]) {
    const deployed = await deployments.deploy(`${contract}_Implementation`, {
      contract,
      from: deployer,
      log: true,
      waitConfirmations: isFork ? 1 : 3,
      ...feeCap,
    });
    const file =
      contract === "LedgityYieldVaultSonic"
        ? "src/protocol-v2/chainSonic/LedgityYieldVaultSonic.sol"
        : `src/protocol-v2/${contract}.sol`;
    await assertFixDeployed(
      deployed.address,
      deployed.deployedBytecode,
      `${file}:${contract}`,
    );
    implementations[contract] = deployed.address;
  }

  console.log("==> LedgityDataProvider".cyan, dataProvider.address);
  for (const vault of vaults)
    console.log(
      `==> ${vault.label} ${vault.proxy}\n    implementation ${live[vault.label].current} -> ${implementations[vault.contract]}\n    highWaterMark ${live[vault.label].highWaterMark} -> ${live[vault.label].pricePerShare} (the price per share now)`
        .cyan,
    );
  console.log("==> Owner".cyan, safe);

  // 3. The Safe batch: per vault, the upgrade then the mark reset
  const vaultInterface = new ethers.utils.Interface(VAULT_ABI);
  const transactions = vaults.flatMap((vault) =>
    [
      vaultInterface.encodeFunctionData("upgradeTo", [
        implementations[vault.contract],
      ]),
      vaultInterface.encodeFunctionData("updateHighWaterMark", [
        live[vault.label].pricePerShare,
      ]),
    ].map((data) => ({
      to: vault.proxy,
      value: "0",
      data,
      contractMethod: null,
      contractInputsValues: null,
    })),
  );

  const batch = {
    version: "1.0",
    chainId: chainId.toString(),
    createdAt: Date.now(),
    meta: {
      name: `Vaults: maintenance upgrade (${label})`,
      description:
        "Upgrade the vaults to their latest implementations and reset the high-water mark to the current price.",
      txBuilderVersion: "1.16.5",
      createdFromSafeAddress: safe,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions,
  };

  const outDir = path.join(__dirname, "..", "data", "safe");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `${label}-vault-fixes.json`);
  fs.writeFileSync(outFile, JSON.stringify(batch, null, 2) + "\n", "utf8");

  console.log(
    `\n==> Safe batch (${transactions.length} transactions) written to`.green,
    path.relative(process.cwd(), outFile),
  );
  console.log(
    `==> Before pushing it: point ledgity-api and the interfaces at LedgityDataProvider ${dataProvider.address}, the vault views stop answering after the upgrade`
      .yellow,
  );
  console.log(
    `==> Push it to the admin page: cd ../ledgity-api && npx tsx scripts/proposeMultisigBundle.ts ${path.relative(path.join(process.cwd(), "..", "ledgity-api"), outFile)}`
      .green,
  );
  console.log(
    `==> (or import it in the Safe Transaction Builder from ${safe}), then run npm run verify:${isFork ? forkName : network.name} for the implementations and LedgityDataProvider`
      .green,
  );
});
