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
    uint256 userAssetBalance;
    uint256 userShareBalance;
    uint256 liquidityManagerBalance;
    uint256 lastFeeTime;
    uint256 lastCompoundTime;
    uint256 highWaterMark;
    uint256 sharePrice;
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

    // Calculate expected buffer balance
    uint256 liquidityBufferRate = vault.liquidityBufferRate();
    uint256 expectedBufferBalance = (expectedState.totalAssets *
      liquidityBufferRate) / RAY;

    uint256 currentBufferBalance = stateBefore.bufferAssets;

    if (currentBufferBalance < expectedBufferBalance) {
      // Buffer needs filling
      uint256 bufferDeficit = expectedBufferBalance -
        currentBufferBalance;
      uint256 bufferAmount = depositAmount < bufferDeficit
        ? depositAmount
        : bufferDeficit;

      expectedState.bufferAssets =
        stateBefore.bufferAssets +
        bufferAmount;
      expectedState.liquidityManagerBalance =
        stateBefore.liquidityManagerBalance +
        (depositAmount - bufferAmount);
    } else {
      // Buffer is full, all goes to liquidity manager
      expectedState.bufferAssets = stateBefore.bufferAssets;
      expectedState.liquidityManagerBalance =
        stateBefore.liquidityManagerBalance +
        depositAmount;
    }

    // User balances
    expectedState.userAssetBalance =
      stateBefore.userAssetBalance -
      depositAmount;
    expectedState.userShareBalance =
      stateBefore.userShareBalance +
      sharesToMint;

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
}
