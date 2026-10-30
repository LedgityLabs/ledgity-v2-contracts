import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";

/**
 * Prepares the upgrade of the live StakingPositions and StakingRewardsDistributor proxies
 * to the implementations fixing the base reward cursors (weeks paid twice, running periods
 * skipped), the distributor storage layout (pendingProtocolFees appended) and the maxTime
 * slope of the locks, on the connected chain:
 *   1. deploys both implementations from the deployer (the Sonic variants on Sonic), the
 *      staking one linked to the chain's existing BalanceLogicLibrary,
 *   2. checks the new bytecode carries the fix and the targets are the staking proxies,
 *   3. writes a Safe Transaction Builder batch: upgradeTo() on the staking proxy, then on the
 *      distributor proxy (read from the staking contract).
 *
 * Nothing is changed on the proxies by this task: their owner is the Safe, which executes
 * the batch from data/safe/<network>-staking-rewards-fix.json.
 *
 * Usage: `npm run upgrade-staking:<chain>` (live) or `npm run upgrade-staking-fork:<chain>`
 * (rehearsal on a hardhat fork, the batch is written all the same).
 */

/// @dev Live StakingPositions proxies, per chain id (the vaults' stakeToken)
const STAKING_BY_CHAIN: Record<number, string> = {
  1: "0xEB4B058BF032E1eD61AA1fEcA332a8b8b96F7483",
  8453: "0x0fCfdF9B6572116FA662A5CF8a074B51EB2D6d88",
  42161: "0x6E83612c73f124127d49eA642c392FF4d9eAFd5b",
  146: "0x613904B9a1Af4450FD34655d123EEb0944888b21",
};

const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const PROXY_ABI = [
  "function owner() view returns (address)",
  "function rewardsDistributor() view returns (address)",
  "function staking() view returns (address)",
  "function upgradeTo(address newImplementation)",
];

/// @dev A function each contract must have, to recognise the proxies and the new implementations
const STAKING_SELECTOR = "function createLock(uint256,uint256)";
const DISTRIBUTOR_SELECTOR = "function depositBaseRewards(uint256,uint256)";

/// @dev Text only the fixed sources contain, checked in the compiled source of the deployed artifact
const FIX_MARKERS: Record<string, string[]> = {
  "src/protocol-v2/staking/StakingPositions.sol": [
    "Reuse the slope recorded at the last checkpoint",
    "revert InvalidMaxTime()",
  ],
  "src/protocol-v2/staking/StakingRewardsDistributor.sol": [
    "_baseRewardOpenPeriodCursor",
    "Appended after the deployed layout",
  ],
};

task(
  "upgrade-staking-rewards-fix",
  "Deploys the fixed staking and rewards distributor implementations and writes the Safe batch upgrading them",
).setAction(async (_, hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, ethers, network } = hre;
  const { deployer } = await getNamedAccounts();
  const chainId = Number(await hre.getChainId());
  const isFork = network.name === "hardhat";
  const forkName = process.env.HARDHAT_DEPLOY_FORK?.toLowerCase();
  const label = isFork ? `${forkName}-fork` : network.name;

  const stakingAddress = STAKING_BY_CHAIN[chainId];
  if (!stakingAddress) throw Error(`No staking to upgrade on chain ${chainId}`);

  console.log(`\n=> Upgrade staking & rewards distributor on ${label}`.cyan);
  console.log("==> Deployer".cyan, deployer);

  // A custom task does not compile by itself: without this the stale artifacts get deployed
  await hre.run("compile");

  // A function selector pushed by the dispatcher (PUSH4 <selector>)
  const has = (code: string, signature: string) => {
    const selector = new ethers.utils.Interface([signature])
      .getSighash(signature.split(" ")[1].split("(")[0])
      .slice(2);
    return code.toLowerCase().includes(`63${selector}`);
  };
  // The deployed bytecode is the artifact just compiled, and that artifact holds the fix
  const assertFixDeployed = async (
    address: string,
    deployedBytecode: string | undefined,
    contractFqn: string,
    libraries: Record<string, string> = {},
  ) => {
    // The recorded bytecode keeps the __$<hash>$__ placeholders: link them like the deploy did
    let linked = (deployedBytecode ?? "").toLowerCase();
    for (const [libraryFqn, libraryAddress] of Object.entries(libraries)) {
      const placeholder = `__$${ethers.utils.id(libraryFqn).slice(2, 36)}$__`;
      linked = linked
        .split(placeholder)
        .join(libraryAddress.slice(2).toLowerCase());
    }
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
    if (!deployedBytecode || onChain !== linked)
      throw Error(
        `${address} does not hold the compiled ${contractFqn}: nothing written`,
      );
    for (const [file, markers] of Object.entries(FIX_MARKERS)) {
      const source = buildInfo?.input.sources[file]?.content ?? "";
      for (const marker of markers)
        if (!source.includes(marker))
          throw Error(
            `${contractFqn} was compiled without the fix (${file} lacks "${marker}"): nothing written`,
          );
    }
  };
  const implementationOf = async (proxy: string) =>
    ethers.utils.getAddress(
      "0x" +
        (await ethers.provider.getStorageAt(proxy, IMPLEMENTATION_SLOT)).slice(
          26,
        ),
    );

  // 1. Targets: the staking proxy, its distributor, and a single Safe owning both
  const staking = await ethers.getContractAt(PROXY_ABI, stakingAddress);
  const distributorAddress: string = await staking.rewardsDistributor();
  const distributor = await ethers.getContractAt(PROXY_ABI, distributorAddress);
  if (
    (await distributor.staking()).toLowerCase() !== stakingAddress.toLowerCase()
  )
    throw Error("The distributor does not point back to the staking proxy");

  const [stakingOwner, distributorOwner] = await Promise.all([
    staking.owner(),
    distributor.owner(),
  ]);
  if (stakingOwner !== distributorOwner)
    throw Error(`Owners differ: ${stakingOwner} / ${distributorOwner}`);
  const safe = stakingOwner;

  // The proxies must run a staking / distributor implementation today (July incident)
  const [currentStakingImpl, currentDistributorImpl] = await Promise.all([
    implementationOf(stakingAddress),
    implementationOf(distributorAddress),
  ]);
  if (!has(await ethers.provider.getCode(currentStakingImpl), STAKING_SELECTOR))
    throw Error(`${stakingAddress} does not run a StakingPositions`);
  if (
    !has(
      await ethers.provider.getCode(currentDistributorImpl),
      DISTRIBUTOR_SELECTOR,
    )
  )
    throw Error(`${distributorAddress} does not run a rewards distributor`);

  // 2. New implementations
  const isSonic = chainId === 146;
  const balanceLogicLibrary = (await deployments.get("BalanceLogicLibrary"))
    .address;

  const stakingImplementation = await deployments.deploy(
    isSonic
      ? "StakingPositionsSonic_Implementation"
      : "StakingPositions_Implementation",
    {
      contract: isSonic ? "StakingPositionsSonic" : "StakingPositions",
      from: deployer,
      log: true,
      waitConfirmations: isFork ? 1 : 3,
      libraries: { BalanceLogicLibrary: balanceLogicLibrary },
    },
  );
  const distributorImplementation = await deployments.deploy(
    isSonic
      ? "StakingRewardsDistributorSonic_Implementation"
      : "StakingRewardsDistributor_Implementation",
    {
      contract: isSonic
        ? "StakingRewardsDistributorSonic"
        : "StakingRewardsDistributor",
      from: deployer,
      log: true,
      waitConfirmations: isFork ? 1 : 3,
    },
  );

  // Never write a batch towards an implementation without the fix, nor towards the wrong
  // contract (the July incident pointed the staking proxy at a vault implementation)
  await assertFixDeployed(
    stakingImplementation.address,
    stakingImplementation.deployedBytecode,
    isSonic
      ? "src/protocol-v2/chainSonic/StakingPositionsSonic.sol:StakingPositionsSonic"
      : "src/protocol-v2/staking/StakingPositions.sol:StakingPositions",
    {
      "src/protocol-v2/libraries/BalanceLogicLibrary.sol:BalanceLogicLibrary":
        balanceLogicLibrary,
    },
  );
  await assertFixDeployed(
    distributorImplementation.address,
    distributorImplementation.deployedBytecode,
    isSonic
      ? "src/protocol-v2/chainSonic/StakingRewardsDistributor.sol:StakingRewardsDistributorSonic"
      : "src/protocol-v2/staking/StakingRewardsDistributor.sol:StakingRewardsDistributor",
  );
  if (
    !has(
      await ethers.provider.getCode(stakingImplementation.address),
      STAKING_SELECTOR,
    ) ||
    !has(
      await ethers.provider.getCode(distributorImplementation.address),
      DISTRIBUTOR_SELECTOR,
    )
  )
    throw Error("A new implementation is not the expected contract");

  console.log(
    `==> StakingPositions ${stakingAddress}\n    implementation ${currentStakingImpl} -> ${stakingImplementation.address}`
      .cyan,
  );
  console.log(
    `==> StakingRewardsDistributor ${distributorAddress}\n    implementation ${currentDistributorImpl} -> ${distributorImplementation.address}`
      .cyan,
  );
  console.log("==> Owner".cyan, safe);

  // 3. The Safe batch, both upgrades in one execution
  const proxyInterface = new ethers.utils.Interface(PROXY_ABI);
  const transactions = [
    [stakingAddress, stakingImplementation.address],
    [distributorAddress, distributorImplementation.address],
  ].map(([to, implementation]) => ({
    to,
    value: "0",
    data: proxyInterface.encodeFunctionData("upgradeTo", [implementation]),
    contractMethod: null,
    contractInputsValues: null,
  }));

  const batch = {
    version: "1.0",
    chainId: chainId.toString(),
    createdAt: Date.now(),
    meta: {
      name: `Staking: rewards cursor & maxTime fix (${label})`,
      description:
        "Upgrade StakingPositions and StakingRewardsDistributor: base rewards no longer pay a week twice nor skip a running period, the distributor storage layout matches the deployed one (pendingProtocolFees appended), and changing maxTime no longer breaks the voting power of existing locks.",
      txBuilderVersion: "1.16.5",
      createdFromSafeAddress: safe,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions,
  };

  const outDir = path.join(__dirname, "..", "data", "safe");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `${label}-staking-rewards-fix.json`);
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
    `==> (or import it in the Safe Transaction Builder from ${safe}), then run npm run verify:${isFork ? forkName : network.name} for the implementations`
      .green,
  );
});
