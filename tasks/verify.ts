import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";
import path from "path";
import { networkConfigs } from "../hardhat.config";

type VerificationRecord = {
  [network: string]: {
    [contractName: string]: {
      address: string;
      implementation?: string;
      verifiedAt: string;
      status: "verified" | "failed";
    };
  };
};

task("verify-deploys", "Verifies all contracts from the latest deployment")
  .addOptionalParam("chain", "Network to verify contracts on")
  .setAction(async (taskArgs, hre: HardhatRuntimeEnvironment) => {
    const network = taskArgs.chain || hre.network.name;
    console.log("network: ", network);
    console.log(`Verifying contracts on ${network}...`);

    // Setup temp directory and verification tracking file
    const tempDir = "temp";
    const verificationFile = path.join(tempDir, "verified-contracts.json");

    if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
    }

    // Load existing verification records
    let verificationRecords: VerificationRecord = {};
    if (fs.existsSync(verificationFile)) {
      verificationRecords = JSON.parse(
        fs.readFileSync(verificationFile, "utf8"),
      );
    }

    // Initialize network record if it doesn't exist
    if (!verificationRecords[network]) {
      verificationRecords[network] = {};
    }

    // Get deployment directory for the current network
    const deploymentsDir = `deployers/deployments/${network}`;

    if (!fs.existsSync(deploymentsDir)) {
      throw new Error(`No deployments found for network ${network}`);
    }

    // Read all deployment files
    const files = fs.readdirSync(deploymentsDir);
    const deployments = files
      .filter((f) => f.endsWith(".json"))
      .map((f) => {
        const content = fs.readFileSync(path.join(deploymentsDir, f), "utf8");
        return {
          name: f.replace(".json", ""),
          ...JSON.parse(content),
        };
      });

    console.log(`Found ${deployments.length} deployments to verify`);

    // Verify each contract
    for (const deployment of deployments) {
      console.log("Constructor arguments: ", deployment.args);

      try {
        // Skip if no implementation (not a contract, just an artifact)
        if (!deployment.address) continue;

        // Check if contract needs verification (new deployment or address changed)
        const existingRecord = verificationRecords[network][deployment.name];
        const addressChanged =
          existingRecord && existingRecord.address !== deployment.address;
        const implChanged =
          existingRecord &&
          deployment.implementation &&
          existingRecord.implementation !== deployment.implementation;

        if (
          existingRecord &&
          existingRecord.status === "verified" &&
          !addressChanged &&
          !implChanged
        ) {
          console.log(
            `\n⏭️  Skipping ${deployment.name} - already verified at ${deployment.address}`,
          );
          continue;
        }

        if (addressChanged) {
          console.log(
            `\n🔍 Address changed for ${deployment.name}: ${existingRecord.address} -> ${deployment.address}`,
          );
        }

        if (implChanged) {
          console.log(
            `\n🔍 Implementation changed for ${deployment.name}: ${existingRecord.implementation} -> ${deployment.implementation}`,
          );
        }

        console.log(`\nVerifying ${deployment.name} at ${deployment.address}`);

        // For proxies, we need to verify the implementation
        const implAddress = deployment.implementation;
        if (implAddress) {
          console.log(
            `Contract is a proxy, verifying implementation at ${implAddress}`,
          );

          // Verify implementation
          await hre.run("verify:verify", {
            address: implAddress,
            constructorArguments: [],
          });

          // Verify proxy
          await hre.run("verify:verify", {
            address: deployment.address,
            constructorArguments: deployment.args || [],
          });

          // Link proxy to implementation on Etherscan
          /// @doc https://docs.etherscan.io/api-endpoints/contracts#verify-proxy-contract
          if (network !== "hedera") {
            const networkConfig = networkConfigs[network];

            await fetch(
              `${networkConfig.apiURL}&module=contract&action=verifyproxycontract&apikey=${networkConfig.verifyApiKey}`,
              {
                method: "POST",
                headers: {
                  "Accept": "application/json",
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({
                  address: deployment.address,
                  expectedimplementation: implAddress,
                }),
              },
            ).catch((err: any) => {
              console.log("Proxy verification failed: ", err);
            });

            console.log("=> Proxy verified successfully");
          }
        } else {
          // Verify non-proxy contract
          await hre.run("verify:verify", {
            address: deployment.address,
            constructorArguments: deployment.args || [],
          });
        }

        // Update verification record
        verificationRecords[network][deployment.name] = {
          address: deployment.address,
          implementation: implAddress,
          verifiedAt: new Date().toISOString(),
          status: "verified",
        };

        // Save after each successful verification
        fs.writeFileSync(
          verificationFile,
          JSON.stringify(verificationRecords, null, 2),
        );

        console.log(`✅ ${deployment.name} verified successfully\n\n`);
      } catch (error: any) {
        if (error.message.includes("already verified")) {
          console.log(`Contract ${deployment.name} is already verified`);

          // Update verification record
          verificationRecords[network][deployment.name] = {
            address: deployment.address,
            implementation: deployment.implementation,
            verifiedAt: new Date().toISOString(),
            status: "verified",
          };

          // Save record
          fs.writeFileSync(
            verificationFile,
            JSON.stringify(verificationRecords, null, 2),
          );
        } else {
          console.error(`❌ Error verifying ${deployment.name}:`, error);

          // Update verification record as failed
          verificationRecords[network][deployment.name] = {
            address: deployment.address,
            implementation: deployment.implementation,
            verifiedAt: new Date().toISOString(),
            status: "failed",
          };

          // Save record
          fs.writeFileSync(
            verificationFile,
            JSON.stringify(verificationRecords, null, 2),
          );
        }
      }
    }

    console.log("\nVerification process completed!");
    console.log(`Verification records saved to: ${verificationFile}`);
  });
