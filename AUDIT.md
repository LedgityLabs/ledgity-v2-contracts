# Security review reference

Read this file before reporting anything. It lists what is deployed, what is not, what has
already been reviewed and accepted, and what is out of scope. Reports that repeat an item
below are not answered.

## Reporting

- Sole contact: victor@ledgity.com. No public GitHub issue for security matters.
- Reports are handled privately. Nothing is published about a report, by either side,
  without a written agreement.
- A report must name the contract, the function, the exact path to a loss or a freeze and,
  when it concerns a deployed contract, the chain and proxy address. A reproducible test is
  welcome. A list of patterns is not a report.
- Automated or AI-assisted reviews must be checked by a person before being sent. The code
  carries `Audit/LLM note:` comments on the functions that are most often misread: read them
  before reporting the function they sit on.

## What is deployed

All contracts are UUPS proxies owned by the protocol Safe. The canonical list of the live
proxies, their chain and the source file each one runs is `tasks/check-storage-layout.ts`:
it is the list the storage checker runs against before every upgrade and is kept current.

| Family | Source | Chains |
| --- | --- | --- |
| Yield vaults (lyUSD, lyEUR) | `src/protocol-v2/LedgityYieldVault.sol`, Sonic: `chainSonic/LedgityYieldVaultSonic.sol` | Ethereum, Base, Arbitrum, Linea, Sonic, Hedera |
| Fixed-term vault (lyREI) | `src/protocol-v2/FixedTermInvestmentVault.sol` | Base |
| Read-only views | `src/protocol-v2/LedgityDataProvider.sol` (stateless, not a proxy) | Ethereum, Base, Arbitrum, Linea, Sonic |
| Staking | `src/protocol-v2/staking/StakingPositions.sol`, `StakingRewardsDistributor.sol`, Sonic variants in `chainSonic/` | Ethereum, Base, Arbitrum, Linea, Sonic, Hedera |
| Legacy LTokens (LUSDC, LEURC) | `src/protocol-v1/LToken.sol` | Base, Arbitrum, Linea, Sonic, withdrawal-only, migrating into the vaults |
| Krystal wrapper | `src/protocol-v2/krystal/KrystalYieldVault.sol` | Ethereum ("LP Strategy") |
| Globals | `GlobalOwner`, `GlobalPause`, `GlobalAccessList` (`GlobalBlacklist` on v1) | every chain |

The last maintenance release upgraded every yield and fixed-term vault on Ethereum, Base,
Arbitrum, Linea and Sonic, plus the Linea staking contracts. The implementations are verified on each
explorer. Hedera was not part of it and is not maintained to the same level: it is out of
scope.

### Deployed but not in use

- `CouncilMerkleDistributor` (Base, Hedera): proxies run the original
  implementation, no merkle root was ever set, no claim was ever made. The repository source
  moved `_claimEpoch` ahead of `claimedBitMap` and has never been deployed; the ordering is
  corrected before any upgrade of it. Not in scope.
- `LegacyStakingTransition` (Ethereum, Base, Arbitrum): proxies run the original
  implementation, the transition it was built for is over. Not in scope.
- `LDYStaking` (protocol v1, Ethereum, Base, Arbitrum, Linea, Sonic): the pre-v2 staking contract. Its perks are no longer
  read by any v2 vault. Withdrawals only, no further upgrade planned. Not in scope.
- `PreMining`, `APRHistory`, `LTokenSignaler`: v1 helpers, no funds at risk through them.

### Not deployed

Anything under `src/` that is not listed above, and any mock under `mock/` directories.

## Out of scope

- Anything that needs the owner, the liquidity manager, the fee recipient or any role holder
  to misbehave, make a mistake or be compromised. The protocol is administered by a multisig
  and the admin surface is a known, accepted trade-off. Centralization findings are not
  answered.
- Hedera, see above.
- Gas optimizations, style, naming, NatSpec, floating pragma remarks, events, and anything
  Slither reports: `audit/slither-report.md` is the baseline and its items are triaged.
- Risks of the external protocols the vaults deposit into (Aave, Krystal) and of the assets
  they hold.
- Front-running, MEV and price-manipulation scenarios on the ERC-4626 preview functions: see
  the accepted deviations below.

## Reviewed and accepted

These were reported, reviewed and accepted as is. Do not report them again.

### Yield vault

- `mint()` applies the deposit maturity impact, so it mints slightly fewer shares than
  requested and returns the shares minted. `withdraw()` returns the assets received. The
  inherited `preview*` functions ignore the maturity impact, the pending fee shares and
  `decimalsOffset`. These are known ERC-4626 deviations: use `deposit()` / `redeem()` with
  `convertToShares()` / `convertToAssets()`.
- `migrateLToken()` charges no maturity impact. The legacy LTokens are withdrawal-only, so the
  exposure is bounded by their remaining supply.
- `setTotalAssets()` is a manual owner-only NAV correction hook.
- `_withdrawFromVault` gates instant exits on the share owner's stake, not the caller's.
- `getFeeData()` on an empty vault or on share dust below `10 ** decimalsOffset`, with a
  non-zero performance fee rate, can set a high-water mark that is not at asset scale. The
  performance fee rate is 0 on every vault and the marks were reset to the price per share in
  the last maintenance release.
- `updateFeeRates()` does not harvest before changing a non-zero rate. Enabling the management
  fee from zero restarts the accrual window at the update time (fixed, deployed in the last
  maintenance release), and `lastFeeTime` now advances on every harvest.
- A fee rate of exactly 100% per year is accepted by `updateFeeRates()`. Owner input, out of
  scope.
- Request fulfillment is an admin or liquidity-manager operation after the request is
  recorded; timing remarks on it are not findings.
- Sonic lyUSD: the Aave USDC reserve on Sonic is frozen by Aave, so deposits revert until Aave
  lifts the cap. Known, external.

### Fixed-term vault (lyREI)

- A cancelled withdrawal request keeps the withdrawal and gas fees already charged. Both are
  0 on lyREI.
- `migrateLToken()` reverts: lyREI has no legacy token.

### Staking

- `StakingPositions.balanceOf()` sums `balanceOfNFTAt()` at the current timestamp, without the
  same-block guard of `balanceOfNFT()`, and loops over every NFT of the address. A borrowed or
  flash-transferred position, or dust NFTs, only affect that address's own vault perks and gas.
  Accepted.
- Dust veLDY positions and the gas they cost their owner. Accepted.
- Transfers to `address(0)` revert since the last maintenance release.
- A restricted (access-listed) position owner could, with an expired lock, let an approved
  operator withdraw the principal or claim the rewards to the operator's address, because
  `withdraw()`, `claim()` and `claimMany()` checked the caller only. Fixed in the source (the
  position owner is checked as well); ships with the next staking
  release. The access list has never been used, so there is no exposure meanwhile.
- `StakingRewardsDistributor` accounts for LDY rewards only; calling the distribution with zero
  stakers is safe, fees accumulate.
- `LDYStaking` (v1) decrements the perk counter on every partial unstake of a position that
  fell below the perk threshold. It only lowers the unstaker's own perks on a contract no v2
  vault reads. Not fixed.

### Krystal wrapper

- Surplus Krystal shares received by `mint()` stay in the wrapper and are counted by
  `totalAssets()`: they accrue to all holders, nothing is stranded.
- The zero-supply branch of `previewMint()` cannot be reached on a live Krystal vault.
- Switching the Krystal vault is an owner operation and does not move funds by itself.
- The wrapper follows the external Krystal flow and does not implement the queued-withdrawal
  and freezable-asset workflow of the Ledgity vaults.

## Disclosure history and acknowledgements

Reports that led to a change are credited here, with the change they led to. Items reviewed
and accepted as is are listed above and are not credited.

- [Nexus Trinity](https://nexustrinity.io/): stale `lastFeeTime` while fees were zero, so
  enabling a management fee would have charged the whole zero-fee period at once and, at an
  extreme rate, reverted every entry point. Owner-triggered only. Fixed in the source the next
  day, deployed with the last maintenance release.
- [Yuriy Khomenkov (KhomDev)](https://khomdev.org): `migrateLToken()` skips the deposit maturity impact, so a
  legacy LToken holder migrating just before a UTC day boundary captured one day of yield.
  Bounded by the legacy supply held outside Ledgity. The legacy LTokens were switched to
  withdrawal-only on every chain, which removes the only way to scale it; migration stays open
  until the legacy tokens are retired.
- [Phil, MainStreet](https://x.com/Mainstreetagent): `burnAndRemintBlacklistedShares()` moved
  the shares with a transfer that the restriction on the holder reverted, so the owner could
  not recover blacklisted shares through it. Rewritten as a burn and a mint, deployed with the
  last maintenance release.
- [Piyush Kumar](https://github.com/pk009900): the `CouncilMerkleDistributor` source orders a
  variable ahead of the deployed layout (noted, corrected before any upgrade of it), and a
  restricted position owner could let an approved operator withdraw or claim on the staking
  contracts. Fixed in the source, ships with the next staking release.

The last maintenance release also fixed, from the internal review: the Aave pool switch
leaving funds in the old pool, a double count of the buffer on fulfillment, duplicate request
ids in `processRequests`, the instant-exit gate reading the caller instead of the owner, the
high-water mark scale, and the staking base-reward cursor and zero-address transfer.

## Upgrade procedure

Every upgrade of a proxy goes through, before any proposal is signed:

1. `tasks/check-storage-layout.ts`: the new layout against the explorer-verified source of the
   running implementation, for every proxy listed.
2. A fork rehearsal of the exact Safe bundle (`npm run test:upgrade-vaults:<chain>`,
   `npm run test:upgrade-staking:<chain>`), including a rollback to the previous
   implementation.
3. Before/after end-to-end tests of the getters and the raw storage slots on the execution
   block (`tests/protocol-v2/integration/*SafeE2E.t.sol`).
4. Contract size against the EIP-170 limit on the hardhat artifacts (`npm run size`).

The bundles are built by `tasks/upgrade-*.ts` and go to the in-house proposal queue, where the
Safe signers review them. Nothing is executed from a developer machine.
