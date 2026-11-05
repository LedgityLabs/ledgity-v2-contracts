import fs from "fs";
import path from "path";

/**
 * Merges several Safe Transaction Builder batches of the same chain and Safe into one, so the
 * owners sign and execute one transaction per chain (e.g. the vault batch and the staking
 * batch). The transactions keep the order of the files given.
 *
 * Usage: npx tsx scripts/mergeSafeBundles.ts <out.json> <name> <in1.json> <in2.json> [...]
 */

const [out, name, ...inputs] = process.argv.slice(2);
if (!out || !name || inputs.length < 2)
  throw new Error(
    "Usage: npx tsx scripts/mergeSafeBundles.ts <out.json> <name> <in1.json> <in2.json> [...]",
  );

const batches = inputs.map((file) =>
  JSON.parse(fs.readFileSync(path.resolve(file), "utf8")),
);
const [first] = batches;
for (const batch of batches) {
  if (batch.chainId !== first.chainId)
    throw new Error(`Chains differ: ${first.chainId} / ${batch.chainId}`);
  if (
    batch.meta.createdFromSafeAddress.toLowerCase() !==
    first.meta.createdFromSafeAddress.toLowerCase()
  )
    throw new Error(
      `Safes differ: ${first.meta.createdFromSafeAddress} / ${batch.meta.createdFromSafeAddress}`,
    );
}

const merged = {
  ...first,
  createdAt: Date.now(),
  meta: {
    ...first.meta,
    name,
    description: batches.map((batch) => batch.meta.description).join(" "),
  },
  transactions: batches.flatMap((batch) => batch.transactions),
};

fs.writeFileSync(path.resolve(out), JSON.stringify(merged, null, 2) + "\n", "utf8");
console.log(
  `${path.resolve(out)}: ${merged.transactions.length} transactions on chain ${merged.chainId} for ${merged.meta.createdFromSafeAddress}`,
);
