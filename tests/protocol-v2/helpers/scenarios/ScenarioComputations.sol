// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";

// Foundry
import { Test } from "foundry/lib/forge-std/src/Test.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
// Libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ScenarioComputations
 * @notice Computation helpers for scenario-based testing
 * @dev Calculates expected state after actions for validation
 */
contract ScenarioComputations is Test, Fixtures {
  using Math for uint256;

  // ======== STRUCTS ======== //

  struct VaultState {
    uint256 totalAssets;
    uint256 totalSupply;
    uint256 bufferAssets;
    uint256 lastFeeTime;
    uint256 lastCompoundTime;
    uint256 highWaterMark;
    uint256 sharePrice;
  }

  struct AccountState {
    uint256 userAssetBalance;
    uint256 userShareBalance;
    uint256 liquidityManagerAssetBalance;
    uint256 feeRecipientShareBalance;
  }

  // ======== DEPOSIT COMPUTATIONS ======== //

  /**
   * @notice Compute expected vault state after a deposit
   * @param stateBefore The vault state before deposit
   * @param depositAmount The amount being deposited
   * @param vault The vault contract
   * @return expectedState The expected state after deposit
   */
  function computeExpectedStateAfterDeposit(
    VaultState memory stateBefore,
    uint256 depositAmount,
    LedgityYieldVault vault
  ) internal view returns (VaultState memory expectedState) {
    // Calculate maturity impact (deployment delay fee)
    uint256 maturityImpact = _computeMaturityImpact(
      depositAmount,
      vault.deploymentDelay(),
      vault.yieldAPR()
    );

    // Net deposit after maturity impact
    uint256 netDeposit = depositAmount - maturityImpact;

    // Calculate shares to mint
    uint256 sharesToMint = _computeSharesForDeposit(
      netDeposit,
      stateBefore.totalSupply,
      stateBefore.totalAssets
    );

    // Expected total assets increases by net deposit
    expectedState.totalAssets = stateBefore.totalAssets + netDeposit;

    // Expected total supply increases by shares minted
    expectedState.totalSupply =
      stateBefore.totalSupply +
      sharesToMint;

    // Buffer stays same (assets distributed separately)
    expectedState.bufferAssets = stateBefore.bufferAssets;

    // Time-based state (may update during deposit due to harvestFees)
    expectedState.lastFeeTime = block.timestamp;
    expectedState.lastCompoundTime = stateBefore.lastCompoundTime;
    expectedState.highWaterMark = stateBefore.highWaterMark;

    // Share price after deposit
    expectedState.sharePrice = _computeSharePrice(
      expectedState.totalAssets,
      expectedState.totalSupply
    );
  }

  /**
   * @notice Compute expected account state after a deposit
   * @param accountBefore The account state before deposit
   * @param depositAmount The amount being deposited
   * @param sharesMinted The shares minted
   * @param stateBefore The vault state before deposit
   * @param vault The vault contract
   * @return expectedAccount The expected account state after deposit
   */
  function computeExpectedAccountsAfterDeposit(
    AccountState memory accountBefore,
    uint256 depositAmount,
    uint256 sharesMinted,
    VaultState memory stateBefore,
    LedgityYieldVault vault
  ) internal view returns (AccountState memory expectedAccount) {
    // User spent assets
    expectedAccount.userAssetBalance =
      accountBefore.userAssetBalance -
      depositAmount;
    // User received shares
    expectedAccount.userShareBalance =
      accountBefore.userShareBalance +
      sharesMinted;

    // Calculate expected buffer balance
    uint256 liquidityBufferRate = vault.liquidityBufferRate();
    uint256 expectedBufferBalance = ((stateBefore.totalAssets +
      depositAmount) * liquidityBufferRate) / RAY;
    uint256 currentBufferBalance = stateBefore.bufferAssets;

    if (currentBufferBalance < expectedBufferBalance) {
      // Buffer needs filling
      uint256 bufferDeficit = expectedBufferBalance -
        currentBufferBalance;
      uint256 bufferAmount = depositAmount < bufferDeficit
        ? depositAmount
        : bufferDeficit;
      expectedAccount.liquidityManagerAssetBalance =
        accountBefore.liquidityManagerAssetBalance +
        (depositAmount - bufferAmount);
    } else {
      // Buffer is full, all goes to liquidity manager
      expectedAccount.liquidityManagerAssetBalance =
        accountBefore.liquidityManagerAssetBalance +
        depositAmount;
    }

    // Fee recipient shares may increase due to harvestFees
    expectedAccount.feeRecipientShareBalance = accountBefore
      .feeRecipientShareBalance;
  }

  // ======== WITHDRAWAL COMPUTATIONS ======== //

  /**
   * @notice Compute expected vault state after a withdrawal
   * @param stateBefore The vault state before withdrawal
   * @param assetsWithdrawn The amount of assets withdrawn
   * @param sharesBurned The shares burned
   * @return expectedState The expected state after withdrawal
   */
  function computeExpectedStateAfterWithdraw(
    VaultState memory stateBefore,
    uint256 assetsWithdrawn,
    uint256 sharesBurned,
    LedgityYieldVault /* vault */
  ) internal view returns (VaultState memory expectedState) {
    // Total assets decrease by gross withdrawal
    expectedState.totalAssets =
      stateBefore.totalAssets -
      assetsWithdrawn;

    // Total supply decreases by shares burned
    expectedState.totalSupply =
      stateBefore.totalSupply -
      sharesBurned;

    // Buffer stays same (assets withdrawn separately)
    expectedState.bufferAssets = stateBefore.bufferAssets;

    // Time-based state (may update during withdrawal due to harvestFees)
    expectedState.lastFeeTime = block.timestamp;
    expectedState.lastCompoundTime = stateBefore.lastCompoundTime;
    expectedState.highWaterMark = stateBefore.highWaterMark;

    // Share price after withdrawal
    expectedState.sharePrice = _computeSharePrice(
      expectedState.totalAssets,
      expectedState.totalSupply
    );
  }

  /**
   * @notice Compute expected account state after a withdrawal
   * @param accountBefore The account state before withdrawal
   * @param assetsWithdrawn The amount of assets withdrawn
   * @param sharesBurned The shares burned
   * @param stateBefore The vault state before withdrawal
   * @return expectedAccount The expected account state after withdrawal
   */
  function computeExpectedAccountsAfterWithdraw(
    AccountState memory accountBefore,
    uint256 assetsWithdrawn,
    uint256 sharesBurned,
    VaultState memory stateBefore,
    LedgityYieldVault /* vault */
  ) internal pure returns (AccountState memory expectedAccount) {
    // User received assets
    expectedAccount.userAssetBalance =
      accountBefore.userAssetBalance +
      assetsWithdrawn;
    // User burned shares
    expectedAccount.userShareBalance =
      accountBefore.userShareBalance -
      sharesBurned;

    // Assets withdrawn from buffer first, then liquidity manager
    uint256 bufferAssets = stateBefore.bufferAssets;
    if (bufferAssets >= assetsWithdrawn) {
      // All from buffer
      expectedAccount.liquidityManagerAssetBalance = accountBefore
        .liquidityManagerAssetBalance;
    } else {
      // Buffer + liquidity manager
      uint256 fromLiquidityManager = assetsWithdrawn - bufferAssets;
      expectedAccount.liquidityManagerAssetBalance =
        accountBefore.liquidityManagerAssetBalance -
        fromLiquidityManager;
    }

    // Fee recipient shares may increase due to harvestFees
    expectedAccount.feeRecipientShareBalance = accountBefore
      .feeRecipientShareBalance;
  }

  // ======== TIME WARP COMPUTATIONS ======== //

  /**
   * @notice Compute expected vault state after time passes
   * @param stateBefore The vault state before time warp
   * @param timeElapsed Time elapsed in seconds
   * @param vault The vault contract
   * @return expectedState The expected state after time warp
   */
  function computeExpectedStateAfterTimeWarp(
    VaultState memory stateBefore,
    uint256 timeElapsed,
    LedgityYieldVault vault
  ) internal view returns (VaultState memory expectedState) {
    // Calculate yield accrual
    uint256 fullDays = timeElapsed / 1 days;
    uint256 accruedAssets = stateBefore.totalAssets;

    if (fullDays > 0) {
      uint256 dailyRate = vault.yieldAPR() / 365;
      for (uint256 i; i < fullDays; i++) {
        accruedAssets = accruedAssets.mulDiv(RAY + dailyRate, RAY);
      }
    }

    expectedState.totalAssets = accruedAssets;
    expectedState.totalSupply = stateBefore.totalSupply;
    expectedState.bufferAssets = stateBefore.bufferAssets;

    // Time-based state updates
    expectedState.lastFeeTime = stateBefore.lastFeeTime;
    expectedState.lastCompoundTime =
      stateBefore.lastCompoundTime +
      (fullDays * 1 days);
    expectedState.highWaterMark = stateBefore.highWaterMark;

    // Share price after time warp
    expectedState.sharePrice = _computeSharePrice(
      expectedState.totalAssets,
      expectedState.totalSupply
    );
  }

  // ======== FEE HARVEST COMPUTATIONS ======== //

  /**
   * @notice Compute expected vault state after fee harvest
   * @param stateBefore The vault state before fee harvest
   * @param vault The vault contract
   * @return expectedState The expected state after fee harvest
   * @return feeSharesMinted The shares minted as fees
   */
  function computeExpectedStateAfterHarvestFees(
    VaultState memory stateBefore,
    LedgityYieldVault vault
  )
    internal
    view
    returns (VaultState memory expectedState, uint256 feeSharesMinted)
  {
    // Calculate fees
    uint256 timeElapsed = block.timestamp - stateBefore.lastFeeTime;

    uint256 managementFeeAssets = computeManagementFees(
      stateBefore.totalAssets,
      vault.managementFeeRate(),
      timeElapsed
    );

    // Calculate performance fees
    uint256 performanceFeeAssets = _computePerformanceFees(
      stateBefore,
      managementFeeAssets,
      vault.performanceFeeRate()
    );

    uint256 totalFeeAssets = managementFeeAssets +
      performanceFeeAssets;

    // Convert fees to shares (accounting for dilution)
    feeSharesMinted = totalFeeAssets.mulDiv(
      stateBefore.totalSupply + 1,
      stateBefore.totalAssets - totalFeeAssets + 1,
      Math.Rounding.Up
    );

    // State after fees
    expectedState.totalAssets = stateBefore.totalAssets;
    expectedState.totalSupply =
      stateBefore.totalSupply +
      feeSharesMinted;
    expectedState.bufferAssets = stateBefore.bufferAssets;
    expectedState.lastFeeTime = block.timestamp;
    expectedState.lastCompoundTime = stateBefore.lastCompoundTime;

    // Update high water mark if needed
    uint256 newSharePrice = _computeSharePrice(
      expectedState.totalAssets,
      expectedState.totalSupply
    );
    expectedState.highWaterMark = newSharePrice >
      stateBefore.highWaterMark
      ? newSharePrice
      : stateBefore.highWaterMark;
    expectedState.sharePrice = newSharePrice;
  }

  /**
   * @notice Compute expected account state after fee harvest
   * @param accountBefore The account state before fee harvest
   * @param feeSharesMinted The shares minted as fees
   * @return expectedAccount The expected account state after fee harvest
   */
  function computeExpectedAccountsAfterHarvestFees(
    AccountState memory accountBefore,
    uint256 feeSharesMinted
  ) internal pure returns (AccountState memory expectedAccount) {
    expectedAccount.userAssetBalance = accountBefore.userAssetBalance;
    expectedAccount.userShareBalance = accountBefore.userShareBalance;
    expectedAccount.liquidityManagerAssetBalance = accountBefore
      .liquidityManagerAssetBalance;
    expectedAccount.feeRecipientShareBalance =
      accountBefore.feeRecipientShareBalance +
      feeSharesMinted;
  }

  // ======== BUFFER OPERATION COMPUTATIONS ======== //

  /**
   * @notice Compute expected vault state after deposit to buffer
   * @param stateBefore The vault state before deposit
   * @param amount The amount deposited to buffer
   * @return expectedState The expected state after deposit
   */
  function computeExpectedStateAfterDepositToBuffer(
    VaultState memory stateBefore,
    uint256 amount
  ) internal pure returns (VaultState memory expectedState) {
    expectedState = stateBefore;
    expectedState.bufferAssets = stateBefore.bufferAssets + amount;
  }

  /**
   * @notice Compute expected account state after deposit to buffer
   * @param accountBefore The account state before deposit
   * @param amount The amount deposited to buffer
   * @return expectedAccount The expected account state after deposit
   */
  function computeExpectedAccountsAfterDepositToBuffer(
    AccountState memory accountBefore,
    uint256 amount
  ) internal pure returns (AccountState memory expectedAccount) {
    expectedAccount = accountBefore;
    expectedAccount.liquidityManagerAssetBalance =
      accountBefore.liquidityManagerAssetBalance -
      amount;
  }

  /**
   * @notice Compute expected vault state after skim buffer
   * @param stateBefore The vault state before skim
   * @param amount The amount skimmed from buffer
   * @return expectedState The expected state after skim
   */
  function computeExpectedStateAfterSkimBuffer(
    VaultState memory stateBefore,
    uint256 amount
  ) internal pure returns (VaultState memory expectedState) {
    expectedState = stateBefore;
    expectedState.bufferAssets = stateBefore.bufferAssets - amount;
  }

  /**
   * @notice Compute expected account state after skim buffer
   * @param accountBefore The account state before skim
   * @param amount The amount skimmed from buffer
   * @return expectedAccount The expected account state after skim
   */
  function computeExpectedAccountsAfterSkimBuffer(
    AccountState memory accountBefore,
    uint256 amount
  ) internal pure returns (AccountState memory expectedAccount) {
    expectedAccount = accountBefore;
    expectedAccount.liquidityManagerAssetBalance =
      accountBefore.liquidityManagerAssetBalance +
      amount;
  }

  // ======== INTERNAL HELPERS ======== //

  /**
   * @notice Calculate maturity impact (deployment delay fee)
   * @param assets The amount of assets being deposited
   * @param deploymentDelay The deployment delay in days
   * @param yieldAPR The yield APR in RAY
   * @return fee The maturity impact fee
   */
  function _computeMaturityImpact(
    uint256 assets,
    uint8 deploymentDelay,
    uint256 yieldAPR
  ) internal pure returns (uint256 fee) {
    if (deploymentDelay == 0) return 0;

    // Calculate compound factor for deployment delay period
    uint256 dailyRate = yieldAPR / 365;

    // Calculate: (1 + dailyRate)^deploymentDelay
    uint256 compoundFactor = RAY;
    for (uint256 i; i < deploymentDelay; i++) {
      compoundFactor = compoundFactor.mulDiv(RAY + dailyRate, RAY);
    }

    // Fee = assets * ((1 + rate)^delay - 1) / (1 + rate)^delay
    fee = (assets * (compoundFactor - RAY)) / compoundFactor;
  }

  /**
   * @notice Calculate shares to mint for a deposit
   * @param netDeposit The net deposit amount (after fees)
   * @param totalSupply Current total supply
   * @param totalAssets Current total assets
   * @return shares The shares to mint
   */
  function _computeSharesForDeposit(
    uint256 netDeposit,
    uint256 totalSupply,
    uint256 totalAssets
  ) internal pure returns (uint256 shares) {
    if (totalSupply == 0 || totalAssets == 0) {
      return netDeposit;
    }

    shares = netDeposit.mulDiv(totalSupply, totalAssets);
  }

  /**
   * @notice Calculate share price
   * @param totalAssets Total vault assets
   * @param totalSupply Total share supply
   * @return price Share price (assets per 1e18 shares)
   */
  function _computeSharePrice(
    uint256 totalAssets,
    uint256 totalSupply
  ) internal pure returns (uint256 price) {
    if (totalSupply == 0) return 1e18;
    return (totalAssets * 1e18) / totalSupply;
  }

  /**
   * @notice Calculate expected yield accrual over time
   * @param initialAssets Starting asset amount
   * @param yieldAPR Annual yield rate in RAY
   * @param timeElapsed Time elapsed in seconds
   * @return accruedAssets Assets after yield accrual
   */
  function computeYieldAccrual(
    uint256 initialAssets,
    uint256 yieldAPR,
    uint256 timeElapsed
  ) internal pure returns (uint256 accruedAssets) {
    if (timeElapsed == 0) return initialAssets;

    uint256 fullDays = timeElapsed / 1 days;
    if (fullDays == 0) return initialAssets;

    uint256 dailyRate = yieldAPR / 365;
    accruedAssets = initialAssets;

    // Apply daily compounding
    for (uint256 i; i < fullDays; i++) {
      accruedAssets = accruedAssets.mulDiv(RAY + dailyRate, RAY);
    }
  }

  /**
   * @notice Calculate expected management fees
   * @param totalAssets Current total assets
   * @param managementFeeRate Management fee rate in RAY
   * @param timeElapsed Time elapsed since last fee
   * @return feeAssets Fee amount in assets
   */
  function computeManagementFees(
    uint256 totalAssets,
    uint256 managementFeeRate,
    uint256 timeElapsed
  ) internal pure returns (uint256 feeAssets) {
    uint256 annualFees = totalAssets.mulDiv(
      managementFeeRate,
      RAY,
      Math.Rounding.Up
    );
    feeAssets = annualFees.mulDiv(
      timeElapsed,
      365 days,
      Math.Rounding.Up
    );
  }

  /**
   * @notice Calculate withdrawal fee
   * @param amount The amount being withdrawn
   * @param withdrawalFeeRate The withdrawal fee rate in RAY
   * @return fee The withdrawal fee amount
   */
  function _computeWithdrawalFee(
    uint256 amount,
    uint256 withdrawalFeeRate
  ) internal pure returns (uint256 fee) {
    fee = amount.mulDiv(withdrawalFeeRate, RAY, Math.Rounding.Up);
  }

  /**
   * @notice Calculate performance fees
   * @param stateBefore The vault state before fees
   * @param managementFeeAssets The management fee assets already calculated
   * @param performanceFeeRate The performance fee rate in RAY
   * @return performanceFeeAssets The performance fee amount
   */
  function _computePerformanceFees(
    VaultState memory stateBefore,
    uint256 managementFeeAssets,
    uint256 performanceFeeRate
  ) internal pure returns (uint256 performanceFeeAssets) {
    // Price per share before performance fees
    uint256 pricePerShare = (stateBefore.totalAssets -
      managementFeeAssets).mulDiv(
        1e18,
        stateBefore.totalSupply + 1,
        Math.Rounding.Up
      );

    if (pricePerShare > stateBefore.highWaterMark) {
      uint256 profitPerShare = pricePerShare -
        stateBefore.highWaterMark;
      uint256 profit = profitPerShare.mulDiv(
        stateBefore.totalSupply,
        1e18,
        Math.Rounding.Up
      );
      performanceFeeAssets = profit.mulDiv(
        performanceFeeRate,
        RAY,
        Math.Rounding.Up
      );
    }
  }

  // ======== VALIDATION FUNCTIONS ======== //

  /**
   * @notice Validate vault state matches expected state
   * @param actual The actual vault state
   * @param expected The expected vault state
   * @param tolerance Relative tolerance for approximate checks (e.g., 0.001e18 = 0.1%)
   */
  function validateVaultState(
    VaultState memory actual,
    VaultState memory expected,
    uint256 tolerance
  ) internal pure {
    assertApproxEqRel(
      actual.totalAssets,
      expected.totalAssets,
      tolerance,
      "VaultState: totalAssets mismatch"
    );
    assertEq(
      actual.totalSupply,
      expected.totalSupply,
      "VaultState: totalSupply mismatch"
    );
    assertEq(
      actual.bufferAssets,
      expected.bufferAssets,
      "VaultState: bufferAssets mismatch"
    );
    assertEq(
      actual.lastFeeTime,
      expected.lastFeeTime,
      "VaultState: lastFeeTime mismatch"
    );
    assertEq(
      actual.lastCompoundTime,
      expected.lastCompoundTime,
      "VaultState: lastCompoundTime mismatch"
    );
    assertApproxEqRel(
      actual.highWaterMark,
      expected.highWaterMark,
      tolerance,
      "VaultState: highWaterMark mismatch"
    );
    assertApproxEqRel(
      actual.sharePrice,
      expected.sharePrice,
      tolerance,
      "VaultState: sharePrice mismatch"
    );
  }

  /**
   * @notice Validate account state matches expected state
   * @param actual The actual account state
   * @param expected The expected account state
   */
  function validateAccountState(
    AccountState memory actual,
    AccountState memory expected
  ) internal pure {
    assertEq(
      actual.userAssetBalance,
      expected.userAssetBalance,
      "AccountState: userAssetBalance mismatch"
    );
    assertEq(
      actual.userShareBalance,
      expected.userShareBalance,
      "AccountState: userShareBalance mismatch"
    );
    assertEq(
      actual.liquidityManagerAssetBalance,
      expected.liquidityManagerAssetBalance,
      "AccountState: liquidityManagerAssetBalance mismatch"
    );
    assertEq(
      actual.feeRecipientShareBalance,
      expected.feeRecipientShareBalance,
      "AccountState: feeRecipientShareBalance mismatch"
    );
  }
}
