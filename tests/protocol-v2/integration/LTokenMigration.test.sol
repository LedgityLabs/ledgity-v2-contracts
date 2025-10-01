// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LTokenMigration_IntegrationTest is Test, Fixtures {
  using Math for uint256;

  LedgityYieldVault public vault;
  MockLToken public lToken;
  IERC20 public asset;

  uint256 public constant PRECISION_TOLERANCE = 1e15; // 0.1% tolerance
  uint256 public constant BASE_AMOUNT = 10000 * 1e18; // 10k tokens

  function setUp() public {
    _setUp();

    // Use mock WETH for consistent 18 decimals
    asset = usdc;
    lToken = _createLToken(asset);
    vault = _createVault(asset, IERC20(address(lToken)));

    // Setup approvals
    _setupApprovalsForVault(vault, asset);

    // Setup L-Token approvals for migration
    vm.prank(testAccount1);
    lToken.approve(address(vault), type(uint256).max);
    vm.prank(testAccount2);
    lToken.approve(address(vault), type(uint256).max);
    vm.prank(testAccount3);
    lToken.approve(address(vault), type(uint256).max);
  }

  // ============ HELPER FUNCTIONS ============ //

  function _mintLTokens(address user, uint256 amount) internal {
    lToken.mint(user, amount);
  }

  function _depositToVault(
    address user,
    uint256 amount
  ) internal returns (uint256 shares) {
    vm.prank(user);
    shares = vault.deposit(amount, user);
  }

  function _migrateLTokens(
    address user,
    uint256 amount
  ) internal returns (uint256 shares) {
    vm.prank(user);
    shares = vault.migrateLToken(amount);
  }

  function _warpDays(uint256 days_) internal {
    vm.warp(block.timestamp + days_ * 1 days);
  }

  function _assertApproxEq(
    uint256 actual,
    uint256 expected,
    string memory message
  ) internal pure {
    if (expected == 0) {
      assertEq(actual, 0, message);
      return;
    }

    uint256 diff = actual > expected
      ? actual - expected
      : expected - actual;
    uint256 tolerance = (expected * PRECISION_TOLERANCE) / 1e18;

    assertLe(
      diff,
      tolerance,
      string.concat(message, " - tolerance exceeded")
    );
  }

  // ============ POSITIVE MIGRATION TESTS ============ //

  function test_basicLTokenMigration() public {
    uint256 migrationAmount = BASE_AMOUNT;

    _mintLTokens(testAccount1, migrationAmount);

    uint256 initialVaultShares = vault.balanceOf(testAccount1);
    uint256 initialLTokenBalance = lToken.balanceOf(testAccount1);
    uint256 initialTotalAssets = vault.totalAssets();
    uint256 initialTotalSupply = vault.totalSupply();

    uint256 shares = _migrateLTokens(testAccount1, migrationAmount);

    // Verify L-Tokens were transferred
    assertEq(
      lToken.balanceOf(testAccount1),
      initialLTokenBalance - migrationAmount,
      "L-Tokens should be transferred"
    );

    // Verify vault shares were minted
    assertEq(
      vault.balanceOf(testAccount1),
      initialVaultShares + shares,
      "Vault shares should be minted"
    );
    assertGt(shares, 0, "Should receive shares from migration");

    // Verify vault state updated
    assertEq(
      vault.totalAssets(),
      initialTotalAssets + migrationAmount,
      "Total assets should increase"
    );
    assertEq(
      vault.totalSupply(),
      initialTotalSupply + shares,
      "Total supply should increase"
    );
  }

  function testFuzz_migrationAmounts(uint256 migrationAmount) public {
    migrationAmount = bound(migrationAmount, 1e18, 1_000_000 * 1e18);

    _mintLTokens(testAccount1, migrationAmount);

    uint256 expectedShares = vault.convertToShares(migrationAmount);
    uint256 actualShares = _migrateLTokens(
      testAccount1,
      migrationAmount
    );

    // Migration should give shares at current conversion rate
    _assertApproxEq(
      actualShares,
      expectedShares,
      "Migration shares should match conversion rate"
    );
  }

  function test_migrationWithExistingVaultActivity() public {
    // First, create some vault activity
    _depositToVault(testAccount2, BASE_AMOUNT);

    // Warp time to accrue some yield
    _warpDays(30);

    // Harvest fees to update vault state
    vault.harvestFees();

    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 pricePerShareBefore = vault.convertToAssets(1e18);
    uint256 expectedShares = vault.convertToShares(migrationAmount);

    uint256 actualShares = _migrateLTokens(
      testAccount1,
      migrationAmount
    );

    // Migration should respect current share price
    _assertApproxEq(
      actualShares,
      expectedShares,
      "Migration should respect current share price"
    );

    // Share price should remain stable after migration
    uint256 pricePerShareAfter = vault.convertToAssets(1e18);
    _assertApproxEq(
      pricePerShareAfter,
      pricePerShareBefore,
      "Share price should remain stable"
    );
  }

  function test_multipleMigrations() public {
    uint256 migrationAmount = BASE_AMOUNT / 3;

    _mintLTokens(testAccount1, migrationAmount * 3);

    // First migration
    uint256 shares1 = _migrateLTokens(testAccount1, migrationAmount);

    // Warp time and harvest fees
    _warpDays(15);
    vault.harvestFees();

    // Second migration
    uint256 shares2 = _migrateLTokens(testAccount1, migrationAmount);

    // Warp time and harvest fees again
    _warpDays(15);
    vault.harvestFees();

    // Third migration
    uint256 shares3 = _migrateLTokens(testAccount1, migrationAmount);

    // Later migrations should give fewer shares due to yield accrual
    assertGe(
      shares1,
      shares2,
      "Second migration should give fewer or equal shares"
    );
    assertGe(
      shares2,
      shares3,
      "Third migration should give fewer or equal shares"
    );

    // Total shares should equal sum of individual migrations
    uint256 totalShares = vault.balanceOf(testAccount1);
    assertEq(
      totalShares,
      shares1 + shares2 + shares3,
      "Total shares should equal sum"
    );
  }

  function test_migrationVsDirectDeposit() public {
    uint256 amount = BASE_AMOUNT;

    // Migration
    _mintLTokens(testAccount1, amount);
    uint256 sharesFromMigration = _migrateLTokens(
      testAccount1,
      amount
    );

    // Direct deposit
    uint256 sharesFromDeposit = _depositToVault(testAccount2, amount);

    // Migration should give more shares since it bypasses deployment delay
    assertGt(
      sharesFromMigration,
      sharesFromDeposit,
      "Migration should give more shares than direct deposit"
    );
  }

  function test_migrationWithDeploymentDelay() public {
    // Set deployment delay for deposits
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(7); // 7 days

    uint256 amount = BASE_AMOUNT;

    // Migration (no deployment delay)
    _mintLTokens(testAccount1, amount);
    uint256 sharesFromMigration = _migrateLTokens(
      testAccount1,
      amount
    );

    // Direct deposit (with deployment delay)
    uint256 sharesFromDeposit = _depositToVault(testAccount2, amount);

    // Calculate compound factor for deployment delay period
    uint256 yieldAPR = vault.yieldAPR();
    uint256 dailyRate = yieldAPR / 365;

    // Calculate: (1 + dailyRate)^deploymentDelay
    uint256 compoundFactor = RAY;
    for (uint256 i; i < 7; i++) {
      compoundFactor = compoundFactor.mulDiv(RAY + dailyRate, RAY);
    }

    // Fee = assets * ((1 + rate)^delay - 1) / (1 + rate)^delay
    // This ensures: (assets - fee) * (1 + rate)^delay = assets
    uint256 expectedFee = (amount * (compoundFactor - RAY)) /
      compoundFactor;
    uint256 expectedShares = amount - expectedFee;

    // Verify migration gives full shares (no deployment delay)
    assertEq(
      sharesFromMigration,
      amount,
      "Migration should receive full shares without deployment delay"
    );

    // Verify direct deposit receives reduced shares (with deployment delay)
    _assertApproxEq(
      sharesFromDeposit,
      expectedShares,
      "Direct deposit should receive shares minus maturity impact"
    );
  }

  // ============ FEE APPLICATION TESTS ============ //

  function test_migrationTriggersManagementFeeCollection() public {
    // Create initial vault activity
    _depositToVault(testAccount2, BASE_AMOUNT);

    // Warp time to accrue management fees
    _warpDays(90); // 3 months

    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    // Migration should trigger fee collection
    _mintLTokens(testAccount1, BASE_AMOUNT);
    _migrateLTokens(testAccount1, BASE_AMOUNT);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);

    // Management fees should have been collected
    assertGt(
      finalFeeRecipientShares,
      initialFeeRecipientShares,
      "Migration should trigger management fee collection"
    );
  }

  function test_migrationTriggersPerformanceFeeCollection() public {
    // Create initial vault activity
    _depositToVault(testAccount2, BASE_AMOUNT);

    // Warp time to generate performance above high water mark
    _warpDays(180); // 6 months for significant yield

    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 initialHighWaterMark = vault.highWaterMark();

    // Migration should trigger fee collection
    _mintLTokens(testAccount1, BASE_AMOUNT);
    _migrateLTokens(testAccount1, BASE_AMOUNT);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 finalHighWaterMark = vault.highWaterMark();

    // Performance fees should have been collected if above high water mark
    if (finalHighWaterMark > initialHighWaterMark) {
      assertGt(
        finalFeeRecipientShares,
        initialFeeRecipientShares,
        "Migration should trigger performance fee collection"
      );
    }
  }

  function test_migrationNoWithdrawalFees() public {
    uint256 migrationAmount = BASE_AMOUNT;

    _mintLTokens(testAccount1, migrationAmount);

    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    _migrateLTokens(testAccount1, migrationAmount);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 withdrawalFeeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    // Migration should not incur withdrawal fees (only management/performance fees)
    // Any fee shares should be from management/performance fees, not withdrawal fees
    uint256 expectedWithdrawalFee = (migrationAmount *
      vault.withdrawalFeeRate()) / RAY;
    uint256 withdrawalFeeAssets = vault.convertToAssets(
      withdrawalFeeShares
    );

    // Withdrawal fee component should be minimal compared to expected withdrawal fee
    assertLt(
      withdrawalFeeAssets,
      expectedWithdrawalFee / 10,
      "Migration should not incur significant withdrawal fees"
    );
  }

  // ============ NEGATIVE TESTS ============ //

  function test_migrationWithZeroAmount_reverts() public {
    _mintLTokens(testAccount1, BASE_AMOUNT);

    vm.prank(testAccount1);
    vm.expectRevert(LedgityYieldVault.ZeroAmount.selector);
    vault.migrateLToken(0);
  }

  function test_migrationWithoutLToken_reverts() public {
    // Create vault without L-Token
    LedgityYieldVault vaultWithoutLToken = _createVaultWithConfig(
      asset,
      IERC20(address(0)), // No L-Token
      true
    );

    _setupApprovalsForVault(vaultWithoutLToken, asset);

    vm.prank(testAccount1);
    vm.expectRevert(LedgityYieldVault.NoLTokenSet.selector);
    vaultWithoutLToken.migrateLToken(BASE_AMOUNT);
  }

  function test_migrationWithInsufficientBalance_reverts() public {
    uint256 migrationAmount = BASE_AMOUNT;
    uint256 actualBalance = migrationAmount / 2;

    _mintLTokens(testAccount1, actualBalance);

    vm.prank(testAccount1);
    vm.expectRevert(); // ERC20 insufficient balance
    vault.migrateLToken(migrationAmount);
  }

  function test_migrationWithInsufficientApproval_reverts() public {
    uint256 migrationAmount = BASE_AMOUNT;

    _mintLTokens(testAccount1, migrationAmount);

    // Reset approval
    vm.prank(testAccount1);
    lToken.approve(address(vault), 0);

    vm.prank(testAccount1);
    vm.expectRevert(); // ERC20 insufficient allowance
    vault.migrateLToken(migrationAmount);
  }

  function test_migrationWhenPaused_reverts() public {
    _mintLTokens(testAccount1, BASE_AMOUNT);

    // Pause the vault
    vm.prank(globalOwner.owner());
    globalPause.pause();

    vm.prank(testAccount1);
    vm.expectRevert(); // Pausable: paused
    vault.migrateLToken(BASE_AMOUNT);
  }

  function test_migrationFromRestrictedAccount_reverts() public {
    _mintLTokens(testAccount1, BASE_AMOUNT);

    // Restrict testAccount1
    vm.prank(globalOwner.owner());
    globalAccessList.restrictAccount(testAccount1);

    vm.prank(testAccount1);
    vm.expectRevert(); // Restricted account
    vault.migrateLToken(BASE_AMOUNT);
  }

  // ============ VALUE PRESERVATION TESTS ============ //

  function test_migrationPreservesTotalValue() public {
    // Create initial vault state
    _depositToVault(testAccount2, BASE_AMOUNT);

    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 totalValueBefore = vault.totalAssets();
    uint256 user2SharesBefore = vault.balanceOf(testAccount2);
    uint256 user2ValueBefore = vault.convertToAssets(
      user2SharesBefore
    );

    _migrateLTokens(testAccount1, migrationAmount);

    uint256 totalValueAfter = vault.totalAssets();
    uint256 user2ValueAfter = vault.convertToAssets(
      user2SharesBefore
    );

    // Total value should increase by migration amount
    assertEq(
      totalValueAfter,
      totalValueBefore + migrationAmount,
      "Total value should increase by migration amount"
    );

    // Existing user value should remain unchanged
    _assertApproxEq(
      user2ValueAfter,
      user2ValueBefore,
      "Existing user value should be preserved"
    );
  }

  function test_migrationDoesNotDiluteExistingHolders() public {
    // Create initial vault state
    _depositToVault(testAccount2, BASE_AMOUNT);

    uint256 pricePerShareBefore = vault.convertToAssets(1e18);

    // Large migration
    uint256 migrationAmount = BASE_AMOUNT * 10;
    _mintLTokens(testAccount1, migrationAmount);
    _migrateLTokens(testAccount1, migrationAmount);

    uint256 pricePerShareAfter = vault.convertToAssets(1e18);

    // Share price should remain stable (no dilution)
    _assertApproxEq(
      pricePerShareAfter,
      pricePerShareBefore,
      "Migration should not dilute existing holders"
    );
  }

  function testFuzz_migrationValueConsistency(
    uint256 migrationAmount,
    uint256 existingAssets
  ) public {
    migrationAmount = bound(migrationAmount, 1e18, 100_000 * 1e18);
    existingAssets = bound(existingAssets, 0, 100_000 * 1e18);

    // Create existing vault state if specified
    if (existingAssets > 0) {
      _depositToVault(testAccount2, existingAssets);
    }

    _mintLTokens(testAccount1, migrationAmount);

    uint256 expectedShares = vault.convertToShares(migrationAmount);
    uint256 actualShares = _migrateLTokens(
      testAccount1,
      migrationAmount
    );

    // Migration should give expected shares at current rate
    _assertApproxEq(
      actualShares,
      expectedShares,
      "Migration shares should be consistent with conversion rate"
    );

    // Verify round-trip conversion
    uint256 convertedAssets = vault.convertToAssets(actualShares);
    _assertApproxEq(
      convertedAssets,
      migrationAmount,
      "Round-trip conversion should be consistent"
    );
  }

  // ============ EDGE CASES ============ //

  function test_migrationWithMaxUint256() public {
    uint256 migrationAmount = type(uint256).max;

    // This should fail due to insufficient balance, not overflow
    vm.prank(testAccount1);
    vm.expectRevert(); // ERC20 insufficient balance
    vault.migrateLToken(migrationAmount);
  }

  function test_migrationToZeroTotalSupply() public {
    // Vault starts with zero total supply
    assertEq(
      vault.totalSupply(),
      0,
      "Vault should start with zero supply"
    );

    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 shares = _migrateLTokens(testAccount1, migrationAmount);

    // First migration to empty vault should get 1:1 ratio
    assertEq(
      shares,
      migrationAmount,
      "First migration should get 1:1 ratio"
    );
  }

  function test_migrationAfterVaultLoss() public {
    // Create initial vault state
    _depositToVault(testAccount2, BASE_AMOUNT);

    // Simulate vault loss
    uint256 lossAmount = BASE_AMOUNT / 4; // 25% loss
    uint256 newTotalAssets = vault.totalAssets() - lossAmount;
    vm.prank(globalOwner.owner());
    vault.setTotalAssets(newTotalAssets);

    // Migration after loss
    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 expectedShares = vault.convertToShares(migrationAmount);
    uint256 actualShares = _migrateLTokens(
      testAccount1,
      migrationAmount
    );

    // Migration should still work correctly at reduced share price
    _assertApproxEq(
      actualShares,
      expectedShares,
      "Migration should work correctly after vault loss"
    );

    // Migrator should get more shares due to reduced price
    assertGt(
      actualShares,
      migrationAmount,
      "Should get more shares due to reduced price"
    );
  }

  function test_migrationGasOptimization() public {
    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    // Measure gas for migration
    vm.prank(testAccount1);
    uint256 gasBefore = gasleft();
    vault.migrateLToken(migrationAmount);
    uint256 gasUsed = gasBefore - gasleft();

    // Gas usage should be reasonable (less than 200k gas)
    assertLt(gasUsed, 200_000, "Migration should be gas efficient");
  }

  // ============ INTEGRATION TESTS ============ //

  function test_migrationFollowedByWithdrawal() public {
    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 shares = _migrateLTokens(testAccount1, migrationAmount);

    // Immediate withdrawal
    uint256 initialBalance = asset.balanceOf(testAccount1);

    deal(address(asset), liquidityManager, migrationAmount);
    vm.prank(liquidityManager);
    vault.depositToBuffer(migrationAmount);

    vm.prank(testAccount1);
    vault.redeem(shares, testAccount1, testAccount1);

    uint256 finalBalance = asset.balanceOf(testAccount1);
    uint256 received = finalBalance - initialBalance;

    // Should receive close to migration amount (minus fees)
    uint256 withdrawalFeeRate = vault.withdrawalFeeRate();
    uint256 expectedFee = (migrationAmount * withdrawalFeeRate) / RAY;
    uint256 expectedReceived = migrationAmount - expectedFee;

    _assertApproxEq(
      received,
      expectedReceived,
      "Should receive expected amount after withdrawal"
    );
  }

  function test_migrationWithSubsequentDeposits() public {
    uint256 migrationAmount = BASE_AMOUNT;
    _mintLTokens(testAccount1, migrationAmount);

    uint256 sharesFromMigration = _migrateLTokens(
      testAccount1,
      migrationAmount
    );

    // Subsequent deposit
    uint256 sharesFromDeposit = _depositToVault(
      testAccount1,
      migrationAmount
    );

    uint256 totalShares = vault.balanceOf(testAccount1);
    assertEq(
      totalShares,
      sharesFromMigration + sharesFromDeposit,
      "Total shares should equal sum"
    );

    // Migration shares should be more valuable due to no deployment delay
    assertGt(
      sharesFromMigration,
      sharesFromDeposit,
      "Migration shares should be more than deposit shares"
    );
  }
}
