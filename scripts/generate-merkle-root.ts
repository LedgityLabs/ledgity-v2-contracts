import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { MerkleTree } from "merkletreejs";
import {
  keccak256,
  parseEther,
  formatEther,
  encodePacked,
  Address,
} from "viem";

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                    CONFIGURATION                                      ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

// Reward Token Configuration
const REWARD_TOKEN_ADDRESS: Address = "0x..."; // Replace with reward token address (e.g., LDY token)
const TOTAL_REWARD_AMOUNT = parseEther("10000"); // Total tokens to distribute for this period

// Distributor Configuration  
const DISTRIBUTOR_ADDRESS: Address = "0x..."; // Replace with CouncilMerkleDistributor contract address

// File Configuration
const ELIGIBLE_ACCOUNTS_FILE = "eligible-accounts.json"; // Input file with eligible accounts
const PREVIOUS_DISTRIBUTION_FILE = "council-rewards-distribution.json"; // Previous rewards (optional)
const OUTPUT_FILE = "council-rewards-distribution.json"; // Output file for merkle tree data

// Distribution Strategy
const DISTRIBUTION_METHOD = "proportional"; // "equal" or "proportional" based on voting power

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                      TYPES                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

type EligibleAccount = {
  address: string;
  averageBalance: string;
  minBalance: string;
  maxBalance: string;
  daysAboveThreshold: number;
  totalDays: number;
};

type EligibleAccountsData = {
  generatedAt: string;
  eligibleAccounts: EligibleAccount[];
  summary: any;
};

type AccountReward = {
  index: bigint;
  account: Address;
  amount: bigint;
  claimed: boolean;
  claimedAt?: string;
  claimedTxHash?: string;
};

type RewardDistribution = {
  merkleRoot: string;
  generatedAt: string;
  periodStart: string;
  periodEnd: string;
  totalRewards: bigint;
  totalAccounts: number;
  accountRewards: AccountReward[];
};

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                 MAIN FUNCTION                                        ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

/**
 * Script to generate merkle root for council reward distribution
 * Combines new period rewards with unclaimed previous rewards
 */
async function generateMerkleRoot(): Promise<{
  merkleRoot: string;
  distribution: RewardDistribution;
  proofs: { [address: string]: string[] };
}> {
  console.log("🌳 Starting merkle root generation...");

  const dataDir = join(__dirname, "..", "data");
  const eligibleAccountsPath = join(dataDir, ELIGIBLE_ACCOUNTS_FILE);
  const outputPath = join(dataDir, OUTPUT_FILE);

  // Load eligible accounts
  if (!existsSync(eligibleAccountsPath)) {
    throw new Error(
      `Eligible accounts file not found: ${eligibleAccountsPath}`,
    );
  }

  console.log("📖 Loading eligible accounts...");
  const eligibleData: EligibleAccountsData = JSON.parse(
    readFileSync(eligibleAccountsPath, "utf8"),
  );

  console.log(
    `👥 Found ${eligibleData.eligibleAccounts.length} eligible accounts`,
  );

  // Load previous distribution if exists
  let previousDistribution: RewardDistribution | null = null;
  if (PREVIOUS_DISTRIBUTION_FILE) {
    const previousPath = join(dataDir, PREVIOUS_DISTRIBUTION_FILE);
    if (existsSync(previousPath)) {
      console.log("📖 Loading previous distribution...");
      previousDistribution = JSON.parse(readFileSync(previousPath, "utf8"));
      console.log(
        `📋 Previous distribution had ${previousDistribution?.accountRewards?.length} accounts`,
      );
    }
  }

  // Calculate total voting power for proportional distribution
  const totalVotingPower = eligibleData.eligibleAccounts.reduce(
    (sum, account) => sum + BigInt(account.averageBalance),
    0n,
  );

  console.log(`⚖️ Total voting power: ${formatEther(totalVotingPower)} tokens`);

  // Calculate new rewards for each account based on voting power
  const newRewardAmount = TOTAL_REWARD_AMOUNT;
  const accountRewards: AccountReward[] = [];

  console.log("💰 Calculating reward distribution...");

  for (let i = 0; i < eligibleData.eligibleAccounts.length; i++) {
    const account = eligibleData.eligibleAccounts[i];
    const votingPower = BigInt(account.averageBalance);

    // Calculate proportional reward
    const newReward = (newRewardAmount * votingPower) / totalVotingPower;

    // Check for unclaimed previous rewards
    let unclaimedReward = 0n;
    let wasPreviouslyClaimed = false;

    if (previousDistribution) {
      const previousAccount = previousDistribution.accountRewards.find(
        (prev) => prev.account.toLowerCase() === account.address.toLowerCase(),
      );

      if (previousAccount && !previousAccount.claimed) {
        unclaimedReward = BigInt(previousAccount.amount);
        console.log(
          `💸 Account ${account.address} has unclaimed reward: ${formatEther(unclaimedReward)}`,
        );
      } else if (previousAccount && previousAccount.claimed) {
        wasPreviouslyClaimed = true;
      }
    }

    const totalReward = newReward + unclaimedReward;

    accountRewards.push({
      index: BigInt(i),
      account: account.address as Address,
      amount: totalReward,
      claimed: false,
    });

    console.log(
      `👤 ${account.address}: ${formatEther(totalReward)} tokens (${formatEther(newReward)} new + ${formatEther(unclaimedReward)} unclaimed)`,
    );
  }

  // Generate merkle tree
  console.log("🌳 Generating merkle tree...");

  const leaves = accountRewards.map((reward) => {
    return keccak256(
      encodePacked(
        ["uint256", "address", "uint256"],
        [reward.index, reward.account, reward.amount],
      ),
    );
  });

  const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const merkleRoot = merkleTree.getHexRoot();

  console.log(`🌳 Merkle root: ${merkleRoot}`);

  // Create distribution data
  const distribution: RewardDistribution = {
    merkleRoot,
    generatedAt: new Date().toISOString(),
    periodStart: eligibleData.summary.periodStart,
    periodEnd: eligibleData.summary.periodEnd,
    totalRewards: accountRewards.reduce(
      (sum, reward) => sum + BigInt(reward.amount),
      0n,
    ),
    totalAccounts: accountRewards.length,
    accountRewards,
  };

  // Save distribution data
  writeFileSync(outputPath, JSON.stringify(distribution, null, 2));
  console.log(`💾 Distribution saved to: ${outputPath}`);

  // Generate merkle proofs for verification
  console.log("🔍 Generating merkle proofs...");
  const proofsPath = join(dataDir, "merkle-proofs.json");
  const proofs: { [address: string]: string[] } = {};

  for (const reward of accountRewards) {
    const leaf = keccak256(
      encodePacked(
        ["uint256", "address", "uint256"],
        [reward.index, reward.account, reward.amount],
      ),
    );
    proofs[reward.account] = merkleTree.getHexProof(leaf);
  }

  writeFileSync(proofsPath, JSON.stringify(proofs, null, 2));
  console.log(`🔍 Proofs saved to: ${proofsPath}`);

  // Print summary
  console.log("\n📋 DISTRIBUTION SUMMARY:");
  console.log(`Merkle Root: ${merkleRoot}`);
  console.log(`Total Accounts: ${accountRewards.length}`);
  console.log(
    `Total Rewards: ${formatEther(distribution.totalRewards)} tokens`,
  );
  console.log(`New Rewards: ${formatEther(TOTAL_REWARD_AMOUNT)} tokens`);

  if (previousDistribution) {
    const unclaimedTotal = accountRewards.reduce((sum, reward) => {
      const previousAccount = previousDistribution!.accountRewards.find(
        (prev) => prev.account.toLowerCase() === reward.account.toLowerCase(),
      );
      if (previousAccount && !previousAccount.claimed) {
        return sum + BigInt(previousAccount.amount);
      }
      return sum;
    }, 0n);
    console.log(
      `Unclaimed from Previous: ${formatEther(unclaimedTotal)} tokens`,
    );
  }

  console.log(
    `Period: ${eligibleData.summary.periodStart} to ${eligibleData.summary.periodEnd}`,
  );

  return {
    merkleRoot,
    distribution,
    proofs,
  };
}

// Function to update claim status (called after someone claims)
async function updateClaimStatus(
  account: string,
  txHash: string,
  distributionFile: string = "council-rewards-distribution.json",
) {
  const dataDir = join(__dirname, "..", "data");
  const distributionPath = join(dataDir, distributionFile);

  if (!existsSync(distributionPath)) {
    throw new Error(`Distribution file not found: ${distributionPath}`);
  }

  const distribution: RewardDistribution = JSON.parse(
    readFileSync(distributionPath, "utf8"),
  );

  const accountReward = distribution.accountRewards.find(
    (reward) => reward.account.toLowerCase() === account.toLowerCase(),
  );

  if (!accountReward) {
    throw new Error(`Account ${account} not found in distribution`);
  }

  if (accountReward.claimed) {
    console.log(`⚠️ Account ${account} already marked as claimed`);
    return;
  }

  accountReward.claimed = true;
  accountReward.claimedAt = new Date().toISOString();
  accountReward.claimedTxHash = txHash;

  writeFileSync(distributionPath, JSON.stringify(distribution, null, 2));
  console.log(`✅ Updated claim status for ${account}`);
}

// Run the script
if (require.main === module) {
  generateMerkleRoot()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("❌ Error:", error);
      process.exit(1);
    });
}

export { generateMerkleRoot, updateClaimStatus };
