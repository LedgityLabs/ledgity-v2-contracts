import { updateClaimStatus } from "./generate-merkle-root";

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                    CONFIGURATION                                      ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

// Account Configuration
const CLAIMING_ACCOUNT = "0x1234567890123456789012345678901234567890"; // Replace with claiming account address
const CLAIM_TX_HASH = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"; // Replace with claim transaction hash

// File Configuration
const DISTRIBUTION_FILE = "council-rewards-distribution.json"; // Distribution file to update

/*
 * ╔═══════════════════════════════════════════════════════════════════════════════════════╗
 * ║                                 MAIN FUNCTION                                        ║
 * ╚═══════════════════════════════════════════════════════════════════════════════════════╝
 */

/**
 * Helper script to update claim status for an account
 * Usage: npx hardhat run scripts/update-claim-status.ts --network <network>
 */
async function main(): Promise<void> {

  console.log(`🔄 Updating claim status for account: ${CLAIMING_ACCOUNT}`);
  console.log(`📝 Transaction hash: ${CLAIM_TX_HASH}`);

  try {
    await updateClaimStatus(CLAIMING_ACCOUNT, CLAIM_TX_HASH, DISTRIBUTION_FILE);
    console.log("✅ Claim status updated successfully");
  } catch (error) {
    console.error("❌ Error updating claim status:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
