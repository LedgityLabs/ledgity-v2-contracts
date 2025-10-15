import { zeroAddress } from "viem";
import {
  getContract,
  parseEther,
  formatEther,
  Address,
} from "viem";
import { writeFileSync } from "fs";
import { join } from "path";
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { stakingPositionsAbi } from "../types/contractTypes";

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                    CONFIGURATION                                      ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

// Contract Configuration
const STAKING_POSITIONS_ADDRESS: Address = "0x..."; // Replace with actual StakingPositions contract address
const START_BLOCK = 0n; // Replace with the block number to start tracking from

// Tracking Period Configuration  
const TRACKING_PERIOD_DAYS = 30; // Number of days to track balances
const SAMPLES_PER_DAY = 4; // How many times per day to sample balances (every 6 hours)

// Eligibility Criteria
const MIN_BALANCE_THRESHOLD = parseEther("1000"); // Minimum balance required (1000 tokens)
const THRESHOLD_PERCENTAGE = 80; // Percentage of time above threshold required for eligibility (80%)

// Network Configuration
const RPC_URL = process.env.RPC_URL || ""; // Set your RPC URL in environment variables
const CHAIN = mainnet; // Change to your target chain

// Output Configuration
const OUTPUT_FILE = "eligible-accounts.json"; // Output file name in the data directory

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                      TYPES                                           ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

type AccountBalance = {
  address: string;
  tokenIds: number[];
  totalVotingPower: bigint;
  timestamp: number;
};

type EligibleAccount = {
  address: string;
  averageBalance: bigint;
  minBalance: bigint;
  maxBalance: bigint;
  daysAboveThreshold: number;
  totalDays: number;
};

type TokenOwnership = {
  tokenId: number;
  owner: string;
};

type OwnerTokens = {
  owner: string;
  tokenIds: number[];
};

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                 MAIN FUNCTION                                        ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

/**
 * Script to track StakingPositions balances over time
 * Monitors transfers, decay, and balances for a specified period
 * Filters accounts that maintained balance above threshold
 */
async function trackStakingBalances(): Promise<void> {
  console.log("🔍 Starting staking balance tracking...");

  // Validate configuration
  if (!RPC_URL) {
    throw new Error("RPC_URL environment variable is required");
  }

  // Setup provider and contract
  const provider = createPublicClient({
    chain: CHAIN,
    transport: http(RPC_URL),
  });

  const stakingPositions = getContract({
    address: STAKING_POSITIONS_ADDRESS,
    abi: stakingPositionsAbi,
    client: provider,
  });

  const currentBlock = await provider.getBlockNumber();
  const startTimestamp =
    Number(
      (await provider.getBlock({ blockNumber: START_BLOCK }))?.timestamp,
    ) || 0;
  const endTimestamp = startTimestamp + TRACKING_PERIOD_DAYS * 24 * 60 * 60;
  const currentTimestamp = Math.floor(Date.now() / 1000);

  console.log(
    `📊 Tracking from block ${START_BLOCK} (${new Date(startTimestamp * 1000).toISOString()})`,
  );
  console.log(`📊 Period: ${TRACKING_PERIOD_DAYS} days`);
  console.log(
    `📊 Min threshold: ${formatEther(MIN_BALANCE_THRESHOLD)} tokens`,
  );

  // Track all unique addresses that have owned NFTs
  let allAddresses: string[] = [];
  let accountBalances: { [address: string]: AccountBalance[] } = {};

  // Get all Transfer events to track ownership changes
  console.log("🔄 Fetching Transfer events...");
  const filter = await provider.createContractEventFilter({
    address: STAKING_POSITIONS_ADDRESS,
    abi: stakingPositionsAbi,
    eventName: "Transfer",
    fromBlock: START_BLOCK,
    toBlock: currentBlock,
  });
  const transferEvents = await provider.getFilterLogs({ filter });

  console.log(`📝 Found ${transferEvents.length} transfer events`);

  // Process transfers to build ownership history
  let tokenOwnership: TokenOwnership[] = [];
  let ownerTokens: OwnerTokens[] = [];

  for (const event of transferEvents) {
    const { from, to, tokenId } = event.args as {
      from: Address;
      to: Address;
      tokenId: bigint;
    };
    const tokenIdNum = Number(tokenId);

    // Remove from previous owner
    if (from !== zeroAddress) {
      const ownerEntry = ownerTokens.find(ot => ot.owner === from);
      if (ownerEntry) {
        ownerEntry.tokenIds = ownerEntry.tokenIds.filter(id => id !== tokenIdNum);
        if (ownerEntry.tokenIds.length === 0) {
          ownerTokens = ownerTokens.filter(ot => ot.owner !== from);
        }
      }
    }

    // Add to new owner
    if (to !== zeroAddress) {
      // Set token ownership
      const existingOwnership = tokenOwnership.find(to => to.tokenId === tokenIdNum);
      if (existingOwnership) {
        existingOwnership.owner = to;
      } else {
        tokenOwnership.push({ tokenId: tokenIdNum, owner: to });
      }

      // Add token to owner
      let ownerEntry = ownerTokens.find(ot => ot.owner === to);
      if (!ownerEntry) {
        ownerEntry = { owner: to, tokenIds: [] };
        ownerTokens.push(ownerEntry);
      }
      if (!ownerEntry.tokenIds.includes(tokenIdNum)) {
        ownerEntry.tokenIds.push(tokenIdNum);
      }

      // Add unique address
      if (!allAddresses.includes(to)) {
        allAddresses.push(to);
      }
    } else {
      // Remove token ownership
      tokenOwnership = tokenOwnership.filter(to => to.tokenId !== tokenIdNum);
    }
  }

  console.log(`👥 Found ${allAddresses.length} unique addresses`);

  // Sample balance checks throughout the period
  const totalSamples = TRACKING_PERIOD_DAYS * SAMPLES_PER_DAY;
  const sampleInterval = (TRACKING_PERIOD_DAYS * 24 * 60 * 60) / totalSamples;

  console.log("📈 Sampling balances over time...");

  for (let i = 0; i <= totalSamples; i++) {
    const sampleTimestamp = startTimestamp + i * sampleInterval;

    if (sampleTimestamp > currentTimestamp) {
      console.log("⏰ Reached current time, stopping sampling");
      break;
    }

    console.log(
      `📊 Sample ${i + 1}/${totalSamples + 1} - ${new Date(sampleTimestamp * 1000).toISOString()}`,
    );

    for (const address of allAddresses) {
      const ownerEntry = ownerTokens.find(ot => ot.owner === address);
      if (!ownerEntry || ownerEntry.tokenIds.length === 0) continue;

      let totalVotingPower = 0n;
      const tokenIds: number[] = [];

      for (const tokenId of ownerEntry.tokenIds) {
        try {
          const balance = await stakingPositions.read.balanceOfNFTAt([
            BigInt(tokenId),
            BigInt(sampleTimestamp),
          ]);
          totalVotingPower += balance;
          tokenIds.push(tokenId);
        } catch (error) {
          // Token might not exist at this timestamp
          continue;
        }
      }

      if (totalVotingPower > 0n) {
        if (!accountBalances[address]) {
          accountBalances[address] = [];
        }
        accountBalances[address].push({
          address,
          tokenIds,
          totalVotingPower,
          timestamp: sampleTimestamp,
        });
      }
    }
  }

  // Analyze accounts and filter eligible ones
  console.log("🔍 Analyzing account eligibility...");
  const eligibleAccounts: EligibleAccount[] = [];

  for (const address of Object.keys(accountBalances)) {
    const balances = accountBalances[address];
    if (balances.length === 0) continue;

    const balanceValues = balances.map((b) => b.totalVotingPower);
    const minBalance = balanceValues.reduce((min, val) =>
      val < min ? val : min,
    );
    const maxBalance = balanceValues.reduce((max, val) =>
      val > max ? val : max,
    );
    const avgBalance =
      balanceValues.reduce((sum, val) => sum + val, 0n) /
      BigInt(balances.length);

    const daysAboveThreshold = balances.filter(
      (b) => b.totalVotingPower >= MIN_BALANCE_THRESHOLD,
    ).length;

    const totalDays = balances.length;
    const thresholdPercentage = (daysAboveThreshold / totalDays) * 100;

    // Check if meets threshold percentage requirement
    if (thresholdPercentage >= THRESHOLD_PERCENTAGE) {
      eligibleAccounts.push({
        address,
        averageBalance: avgBalance,
        minBalance: minBalance,
        maxBalance: maxBalance,
        daysAboveThreshold,
        totalDays,
      });
    }
  }

  console.log(`✅ Found ${eligibleAccounts.length} eligible accounts`);

  // Save results
  const outputPath = join(__dirname, "..", "data", OUTPUT_FILE);
  const outputData = {
    generatedAt: new Date().toISOString(),
    eligibleAccounts: eligibleAccounts.map(acc => ({
      ...acc,
      averageBalance: acc.averageBalance.toString(),
      minBalance: acc.minBalance.toString(),
      maxBalance: acc.maxBalance.toString(),
    })),
    summary: {
      totalAddresses: allAddresses.length,
      eligibleAddresses: eligibleAccounts.length,
      periodStart: new Date(startTimestamp * 1000).toISOString(),
      periodEnd: new Date(endTimestamp * 1000).toISOString(),
      trackingPeriodDays: TRACKING_PERIOD_DAYS,
      minBalanceThreshold: formatEther(MIN_BALANCE_THRESHOLD),
      thresholdPercentageRequired: THRESHOLD_PERCENTAGE,
    },
  };

  writeFileSync(outputPath, JSON.stringify(outputData, null, 2));
  console.log(`💾 Results saved to: ${outputPath}`);

  // Print summary
  console.log("\n📋 SUMMARY:");
  console.log(`Total addresses tracked: ${allAddresses.length}`);
  console.log(`Eligible addresses: ${eligibleAccounts.length}`);
  console.log(`Threshold: ${formatEther(MIN_BALANCE_THRESHOLD)} tokens`);
  console.log(`Period: ${TRACKING_PERIOD_DAYS} days`);

  if (eligibleAccounts.length > 0) {
    const totalEligibleBalance = eligibleAccounts.reduce(
      (sum, acc) => sum + acc.averageBalance,
      0n,
    );
    console.log(
      `Total eligible balance: ${formatEther(totalEligibleBalance)} tokens`,
    );
    console.log(
      `Average balance per eligible account: ${formatEther(totalEligibleBalance / BigInt(eligibleAccounts.length))} tokens`,
    );
  }
}

// Run the script
if (require.main === module) {
  trackStakingBalances()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error("❌ Error:", error);
      process.exit(1);
    });
}

export { trackStakingBalances };
