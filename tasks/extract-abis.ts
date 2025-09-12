/** TheGraph YAML file requires ABI to be available as top level files (not nested in
 * deployments.json), this script extracts ABIs from hardhat artifacts folder into
 * individual files under contracts/abis/ folder.
 */

import * as fs from "fs";
import * as path from "path";
import { task } from "hardhat/config";

task("extract-abis", "Extracts the ABI").setAction(async (taskArgs, hre) => {
  // __dirname is available globally in CommonJS

  const sourceDirectory = path.join(__dirname, "../artifacts/src");
  const destinationDirectory = path.join(__dirname, "../data/abis");

  // Check if source directory exists
  if (!fs.existsSync(sourceDirectory)) {
    console.error(`Source directory does not exist: ${sourceDirectory}`);
    return;
  }

  // Ensure 'contracts/abis/' directory exists or create it.
  if (!fs.existsSync(destinationDirectory)) {
    fs.mkdirSync(destinationDirectory, { recursive: true });
  }

  const extractABIsFromDirectory = async (directory: string) => {
    if (!fs.existsSync(directory)) {
      console.warn(`Directory does not exist: ${directory}`);
      return;
    }

    const files = fs.readdirSync(directory);

    for (const file of files) {
      const filePath = path.join(directory, file);
      const stat = fs.statSync(filePath);

      if (stat.isDirectory()) {
        await extractABIsFromDirectory(filePath);
      } else if (
        filePath.endsWith(".json") &&
        !filePath.endsWith(".dbg.json")
      ) {
        const contractData = require(filePath);
        const contractName = path.basename(filePath, ".json");
        if (contractData.abi && contractData.abi.length > 0) {
          fs.writeFileSync(
            path.join(destinationDirectory, `${contractName}.json`),
            JSON.stringify(contractData.abi, null, 2),
          );
        } else {
          console.log(`No ABI found for ${contractName}`);
        }
      }
    }
  };

  await extractABIsFromDirectory(sourceDirectory)
    .then(() => {
      console.log("ABIs extracted successfully!");
    })
    .catch((err) => {
      console.error("Error extracting ABIs:", err);
    });
});
