import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
  TASK_COMPILE_SOLIDITY_RUN_SOLC,
  TASK_COMPILE_SOLIDITY_RUN_SOLCJS,
} from "hardhat/builtin-tasks/task-names";
import { execSync } from "child_process";

/**
 * Checks, before any upgrade, that the repository version of each upgradeable contract keeps
 * the storage layout of the implementation its live proxy runs today:
 *   - the live implementation is read from the proxy on chain,
 *   - its source is the explorer-verified standard JSON input (the explorer only verifies a
 *     source that compiles to the deployed bytecode),
 *   - both sources are compiled with solc for their storage layout only,
 *   - every deployed variable must keep its slot, offset and type (struct members and
 *     mapping types included); a rename is reported, a new variable is accepted only after
 *     the end of the deployed layout.
 *
 * Usage: `npm run check:storage-layout:<chain>`; `npm run check:storage-layout:self-test`
 * runs the same comparison against the distributor of 31a1123 (pendingProtocolFees inserted
 * mid-storage) and fails if that corruption is NOT detected.
 */

type Target = { label: string; proxy: string; candidate: string };

/// @dev Deliberate renames, deployed name -> repository name. Any other rename is an error: a
///      shifted variable of the same type (two mappings) only shows up as a rename.
const ALLOWED_RENAMES: Record<string, Record<string, string>> = {
  "src/protocol-v2/staking/StakingRewardsDistributor.sol:StakingRewardsDistributor":
    {
      baseRewardPeriodCursor: "_deprecatedBaseRewardPeriodCursor",
    },
  "src/protocol-v2/chainSonic/StakingRewardsDistributor.sol:StakingRewardsDistributorSonic":
    {
      baseRewardPeriodCursor: "_deprecatedBaseRewardPeriodCursor",
    },
};

const STAKING = "src/protocol-v2/staking/StakingPositions.sol:StakingPositions";
const DISTRIBUTOR =
  "src/protocol-v2/staking/StakingRewardsDistributor.sol:StakingRewardsDistributor";
const LTOKEN = "src/protocol-v1/LToken.sol:LToken";
const VAULT = "src/protocol-v2/LedgityYieldVault.sol:LedgityYieldVault";
const FIXED_TERM_VAULT =
  "src/protocol-v2/FixedTermInvestmentVault.sol:FixedTermInvestmentVault";

const TARGETS_BY_CHAIN: Record<number, Target[]> = {
  1: [
    {
      label: "StakingPositions",
      proxy: "0xEB4B058BF032E1eD61AA1fEcA332a8b8b96F7483",
      candidate: STAKING,
    },
    {
      label: "StakingRewardsDistributor",
      proxy: "0xd8FefECC48D0B7a250314CD67D7F73fF3a35b6BF",
      candidate: DISTRIBUTOR,
    },
    {
      label: "lyUSD",
      proxy: "0x3C769d0e8D21d380228dFB7918c6933bb6ecB6D4",
      candidate: VAULT,
    },
    {
      label: "lyEUR",
      proxy: "0x20968165B7d2cDF33aF632aAB3e0539848d44BC8",
      candidate: VAULT,
    },
  ],
  8453: [
    {
      label: "StakingPositions",
      proxy: "0x0fCfdF9B6572116FA662A5CF8a074B51EB2D6d88",
      candidate: STAKING,
    },
    {
      label: "StakingRewardsDistributor",
      proxy: "0x2ab82B69aB88e6174425234c4da50b2EdFC217c1",
      candidate: DISTRIBUTOR,
    },
    {
      label: "LUSDC",
      proxy: "0x3C769d0e8D21d380228dFB7918c6933bb6ecB6D4",
      candidate: LTOKEN,
    },
    {
      label: "LEURC",
      proxy: "0x77ce973744745310359B0d1a3415A34FF983708F",
      candidate: LTOKEN,
    },
    {
      label: "lyUSD",
      proxy: "0x916f179D5D9B7d8Ad815AC2f8570aabF0C6a6e38",
      candidate: VAULT,
    },
    {
      label: "lyEUR",
      proxy: "0xFaA1e3720e6Ef8cC76A800DB7B3dF8944833b134",
      candidate: VAULT,
    },
    {
      label: "lyREI",
      proxy: "0x085b292A7c54767d5371fE939a4Ad4dC9828d98f",
      candidate: FIXED_TERM_VAULT,
    },
  ],
  42161: [
    {
      label: "StakingPositions",
      proxy: "0x6E83612c73f124127d49eA642c392FF4d9eAFd5b",
      candidate: STAKING,
    },
    {
      label: "StakingRewardsDistributor",
      proxy: "0x841A13A5C4Aa89d7C013E6f49E95188ed3e6c300",
      candidate: DISTRIBUTOR,
    },
    {
      label: "LUSDC",
      proxy: "0xd54d564606611A3502FE8909bBD3075dbeb77813",
      candidate: LTOKEN,
    },
    {
      label: "lyUSD",
      proxy: "0x283F35b6406a0e19a786ed119869eF2c0fE157Ee",
      candidate: VAULT,
    },
  ],
  59144: [
    {
      label: "StakingPositions",
      proxy: "0xcc1beF907DCe6c073332A75086708F53BDe4f6f0",
      candidate: STAKING,
    },
    {
      label: "StakingRewardsDistributor",
      proxy: "0x902982C0C405091894FF82b3b51F180f99f75144",
      candidate: DISTRIBUTOR,
    },
    {
      label: "LUSDC",
      proxy: "0x4AF215DbE27fc030F37f73109B85F421FAB45B7a",
      candidate: LTOKEN,
    },
    {
      label: "lyUSD",
      proxy: "0x43b3c64dbc95F9eD83795E051fc00014059e698F",
      candidate: VAULT,
    },
  ],
  146: [
    {
      label: "StakingPositionsSonic",
      proxy: "0x613904B9a1Af4450FD34655d123EEb0944888b21",
      candidate:
        "src/protocol-v2/chainSonic/StakingPositionsSonic.sol:StakingPositionsSonic",
    },
    {
      label: "StakingRewardsDistributorSonic",
      proxy: "0x536E1C104F89351A2156135FA85B9B2dC26d9462",
      candidate:
        "src/protocol-v2/chainSonic/StakingRewardsDistributor.sol:StakingRewardsDistributorSonic",
    },
    {
      label: "LUSDC",
      proxy: "0xD7cCABfBEfE332C9784FF3debeBdDbc787E75e69",
      candidate: "src/protocol-v1/sonic/LTokenSonic.sol:LTokenSonic",
    },
    {
      label: "LEURC",
      proxy: "0x88dC8674339731A12a08624f455Fd41Fe2d6DC82",
      candidate: "src/protocol-v1/sonic/LTokenSonic.sol:LTokenSonic",
    },
    {
      label: "lyUSD",
      proxy: "0x65f75c675Cc76474662DfBF7B6e8683764223001",
      candidate: 
        "src/protocol-v2/chainSonic/LedgityYieldVaultSonic.sol:LedgityYieldVaultSonic",
    },
  ],
};

const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const SOLC_VERSION = "0.8.18";

type StorageItem = {
  label: string;
  slot: string;
  offset: number;
  type: string;
};
type StorageType = {
  encoding: string;
  label: string;
  numberOfBytes: string;
  key?: string;
  value?: string;
  base?: string;
  members?: StorageItem[];
};
type Layout = {
  storage: StorageItem[];
  types: Record<string, StorageType> | null;
};

/// @dev A type as a string independent of AST ids, so two compilations compare
function describe(typeId: string, types: Record<string, StorageType>): string {
  const type = types[typeId];
  if (!type) return typeId;
  if (type.encoding === "mapping")
    return `mapping(${describe(type.key!, types)} => ${describe(type.value!, types)})`;
  if (type.encoding === "dynamic_array")
    return `${describe(type.base!, types)}[]`;
  if (type.members)
    return `struct{${type.members
      .map((m) => `${m.slot}:${m.offset}:${describe(m.type, types)}`)
      .join(",")}}`;
  if (type.base) return `${describe(type.base, types)}[${type.numberOfBytes}b]`;
  // A contract or interface reference, or a payable address, is an address in storage
  if (type.label.startsWith("contract ") || type.label === "address payable")
    return "address";
  if (type.label.startsWith("enum ")) return `enum(${type.numberOfBytes}b)`;
  return type.label;
}

/// @dev Number of bytes a variable occupies, to find the end of a layout
const sizeOf = (item: StorageItem, types: Record<string, StorageType>) =>
  Number(types[item.type]?.numberOfBytes ?? 32);

export function compareLayouts(
  deployed: Layout,
  candidate: Layout,
  allowedRenames: Record<string, string> = {},
) {
  const errors: string[] = [];
  const notes: string[] = [];
  const dTypes = deployed.types ?? {};
  const cTypes = candidate.types ?? {};

  for (const d of deployed.storage) {
    const c = candidate.storage.find(
      (item) => item.slot === d.slot && item.offset === d.offset,
    );
    const dType = describe(d.type, dTypes);
    if (!c) {
      errors.push(`slot ${d.slot}+${d.offset} "${d.label}" (${dType}) is gone`);
      continue;
    }
    const cType = describe(c.type, cTypes);
    if (dType !== cType)
      errors.push(
        `slot ${d.slot}+${d.offset} "${d.label}" ${dType} -> "${c.label}" ${cType}`,
      );
    else if (d.label !== c.label) {
      if (allowedRenames[d.label] === c.label)
        notes.push(
          `slot ${d.slot}+${d.offset} renamed "${d.label}" -> "${c.label}" (allowed)`,
        );
      else
        errors.push(
          `slot ${d.slot}+${d.offset} "${d.label}" now holds "${c.label}" (same type: a shift or an unlisted rename)`,
        );
    }
  }

  // The first byte after the deployed layout: anything new must start there or later
  let deployedEnd = 0n;
  for (const d of deployed.storage) {
    const end =
      BigInt(d.slot) * 32n + BigInt(d.offset) + BigInt(sizeOf(d, dTypes));
    if (end > deployedEnd) deployedEnd = end;
  }
  for (const c of candidate.storage) {
    const known = deployed.storage.some(
      (d) => d.slot === c.slot && d.offset === c.offset,
    );
    if (known) continue;
    const start = BigInt(c.slot) * 32n + BigInt(c.offset);
    if (start < deployedEnd)
      errors.push(
        `new "${c.label}" (${describe(c.type, cTypes)}) at slot ${c.slot}+${c.offset} lands inside the deployed layout`,
      );
    else notes.push(`appended "${c.label}" at slot ${c.slot}`);
  }
  return { errors, notes };
}

task(
  "check-storage-layout",
  "Compares the storage layout of the repository contracts with the implementations their live proxies run",
)
  .addFlag(
    "selfTest",
    "Check that the corrupt distributor of 31a1123 is rejected",
  )
  .setAction(async ({ selfTest }, hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const chainId = Number(await hre.getChainId());
    const targets = TARGETS_BY_CHAIN[chainId];
    if (!targets)
      throw Error(`No upgradeable target listed for chain ${chainId}`);
    const apiKey = process.env.ETHERSCAN_API_KEY;
    if (!apiKey) throw Error("ETHERSCAN_API_KEY is not set");

    await hre.run("compile", { quiet: true });

    const solcBuild = await hre.run(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, {
      quiet: true,
      solcVersion: SOLC_VERSION,
    });
    const layoutOf = async (
      input: any,
      file: string,
      name: string,
    ): Promise<Layout> => {
      const request = {
        ...input,
        settings: {
          ...input.settings,
          outputSelection: { [file]: { [name]: ["storageLayout"] } },
        },
      };
      const output = solcBuild.isSolcJs
        ? await hre.run(TASK_COMPILE_SOLIDITY_RUN_SOLCJS, {
            input: request,
            solcJsPath: solcBuild.compilerPath,
          })
        : await hre.run(TASK_COMPILE_SOLIDITY_RUN_SOLC, {
            input: request,
            solcPath: solcBuild.compilerPath,
            solcVersion: SOLC_VERSION,
          });
      const errors = (output.errors ?? []).filter(
        (e: any) => e.severity === "error",
      );
      if (errors.length)
        throw Error(
          `${file}:${name} does not compile: ${errors[0].formattedMessage}`,
        );
      const layout = output.contracts?.[file]?.[name]?.storageLayout;
      if (!layout) throw Error(`No storage layout for ${file}:${name}`);
      return layout;
    };

    // The explorer-verified source of the implementation the proxy runs today
    const deployedLayoutOf = async (proxy: string) => {
      const raw = await ethers.provider.getStorageAt(
        proxy,
        IMPLEMENTATION_SLOT,
      );
      const implementation = ethers.utils.getAddress("0x" + raw.slice(26));
      const url = `https://api.etherscan.io/v2/api?chainid=${chainId}&module=contract&action=getsourcecode&address=${implementation}&apikey=${apiKey}`;
      const answer = await (await fetch(url)).json();
      const result = answer?.result?.[0];
      if (!result?.SourceCode)
        throw Error(`${implementation} is not verified on the explorer`);
      if (!result.CompilerVersion.startsWith(`v${SOLC_VERSION}+`))
        throw Error(
          `${implementation} was compiled with ${result.CompilerVersion}`,
        );
      const source: string = result.SourceCode;
      if (!source.startsWith("{{"))
        throw Error(
          `${implementation} is verified from a flattened file, not a standard JSON input`,
        );
      const input = JSON.parse(source.slice(1, -1));
      const name: string = result.ContractName;
      const file = Object.keys(input.sources).find((path) =>
        new RegExp(`\\bcontract\\s+${name}\\b`).test(
          input.sources[path].content,
        ),
      );
      if (!file)
        throw Error(
          `contract ${name} not found in the verified source of ${implementation}`,
        );
      // Etherscan answers quickly but rate-limits: stay under it
      await new Promise((resolve) => setTimeout(resolve, 400));
      return {
        implementation,
        name,
        layout: await layoutOf(input, file, name),
      };
    };

    const candidateLayoutOf = async (
      fqn: string,
      override?: { file: string; content: string },
    ) => {
      const [file, name] = fqn.split(":");
      const buildInfo = await hre.artifacts.getBuildInfo(fqn);
      if (!buildInfo) throw Error(`No build info for ${fqn}`);
      const input = JSON.parse(JSON.stringify(buildInfo.input));
      if (override)
        input.sources[override.file] = { content: override.content };
      return layoutOf(input, file, name);
    };

    if (selfTest) {
      const target = targets.find((t) => t.candidate === DISTRIBUTOR);
      if (!target)
        throw Error(
          "Run the self-test on a chain with the distributor (mainnet, base, arbitrum)",
        );
      const file = DISTRIBUTOR.split(":")[0];
      const corrupt = execSync(`git show 31a1123:${file}`, {
        encoding: "utf8",
      });
      const deployed = await deployedLayoutOf(target.proxy);
      const { errors } = compareLayouts(
        deployed.layout,
        await candidateLayoutOf(DISTRIBUTOR, { file, content: corrupt }),
        ALLOWED_RENAMES[DISTRIBUTOR],
      );
      if (errors.length === 0)
        throw Error(
          "Self-test FAILED: the corrupt distributor of 31a1123 was not detected",
        );
      console.log(
        `Self-test passed: the distributor of 31a1123 is rejected (${errors.length} incompatibilities), e.g.`,
      );
      for (const error of errors.slice(0, 4)) console.log(`  ${error}`);
      const identity = compareLayouts(deployed.layout, deployed.layout);
      if (identity.errors.length)
        throw Error("Self-test FAILED: a layout differs from itself");
      console.log("Self-test passed: the deployed layout matches itself");
      return;
    }

    let failures = 0;
    for (const target of targets) {
      const deployed = await deployedLayoutOf(target.proxy);
      const candidate = await candidateLayoutOf(target.candidate);
      const { errors, notes } = compareLayouts(
        deployed.layout,
        candidate,
        ALLOWED_RENAMES[target.candidate],
      );
      const status = errors.length ? "INCOMPATIBLE".red : "compatible".green;
      console.log(
        `${target.label} ${target.proxy} (live ${deployed.name} ${deployed.implementation}, ${deployed.layout.storage.length} variables) -> ${target.candidate.split(":")[1]}: ${status}`,
      );
      for (const error of errors) console.log(`  ERROR ${error}`.red);
      for (const note of notes) console.log(`  ${note}`);
      failures += errors.length;
    }
    if (failures)
      throw Error(`${failures} storage incompatibilities: do not upgrade`);
  });
