// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultComputations_FuzzTest is Test, Fixtures {
  LedgityYieldVault public vault;
  MockLToken public lToken;
  IERC20 public asset;

  uint256 public constant PRECISION_TOLERANCE = 1e15; // 0.1% tolerance for precision errors
  uint256 public constant BASE_DEPOSIT = 10000 * 1e18; // 10k tokens

  function setUp() public {
    _setUp();

    // Use mock WETH for consistent 18 decimals
    asset = mockWeth;
    lToken = _createLToken(asset);
    vault = _createVault(asset, IERC20(address(lToken)));

    // Setup approvals
    _setupApprovalsForVault(vault, asset);
  }

  // ============ HELPER FUNCTIONS ============ //

  function _depositToVault(
    address user,
    uint256 amount
  ) internal returns (uint256 shares) {
    vm.prank(user);
    shares = vault.deposit(amount, user);
  }

  function _warpDays(uint256 days_) internal {
    vm.warp(block.timestamp + days_ * 1 days);
  }

  function _calculateExpectedCompoundedAssets(
    uint256 initialAssets,
    uint256 apr,
    uint256 days_
  ) internal pure returns (uint256) {
    uint256 dailyRate = apr / 365;
    uint256 compoundedAssets = initialAssets;

    for (uint256 i = 0; i < days_; i++) {
      compoundedAssets = (compoundedAssets * (RAY + dailyRate)) / RAY;
    }

    return compoundedAssets;
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

  // ============ BUFFER TESTS ============ //

  function testFuzz_bufferAutoBalancing(
    uint256 depositAmount
  ) public {
    // Bound deposit amount to reasonable range
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);

    uint256 expectedBufferRate = vault.liquidityBufferRate();

    // Initial deposit
    _depositToVault(testAccount1, depositAmount);

    uint256 totalAssets = vault.totalAssets();
    uint256 expectedBuffer = (totalAssets * expectedBufferRate) / RAY;
    uint256 actualBuffer = vault.getBufferAssets();

    // Buffer should be balanced according to liquidityBufferRate
    _assertApproxEq(
      actualBuffer,
      expectedBuffer,
      "Buffer not properly balanced"
    );
  }

  function testFuzz_bufferCompoundingWithStrategy(
    uint256 depositAmount,
    uint256 days_
  ) public {
    // Only test with Aave-enabled vaults
    if (!vault.hasBufferStrategy()) return;

    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialBufferAssets = vault.getBufferAssets();
    uint256 initialTotalAssets = vault.totalAssets();

    _warpDays(days_);

    uint256 finalBufferAssets = vault.getBufferAssets();
    uint256 finalTotalAssets = vault.totalAssets();

    // Buffer should have grown due to Aave rewards (if any)
    assertGe(
      finalBufferAssets,
      initialBufferAssets,
      "Buffer assets should not decrease"
    );

    // Total assets should have grown due to vault APR
    assertGt(
      finalTotalAssets,
      initialTotalAssets,
      "Total assets should increase over time"
    );
  }

  function test_bufferRewardsDoNotAffectShareValue() public {
    if (!vault.hasBufferStrategy()) return;

    _depositToVault(testAccount1, BASE_DEPOSIT);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialPricePerShare = vault.convertToAssets(1e18);

    // Simulate buffer earning rewards by manually adding assets to buffer
    uint256 bufferRewards = 1000 * 1e18;
    deal(
      address(asset),
      address(vault),
      asset.balanceOf(address(vault)) + bufferRewards
    );

    uint256 finalPricePerShare = vault.convertToAssets(1e18);

    // Share value should remain stable despite buffer rewards
    _assertApproxEq(
      finalPricePerShare,
      initialPricePerShare,
      "Buffer rewards should not affect share price"
    );
    assertEq(
      vault.balanceOf(testAccount1),
      initialShares,
      "User shares should remain unchanged"
    );
  }

  // ============ MANAGEMENT FEE TESTS ============ //

  function testFuzz_managementFeeAccrual(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 managementFeeRate = vault.managementFeeRate();

    _warpDays(days_);

    vault.harvestFees();

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 feeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    // Calculate expected management fee
    uint256 totalAssets = vault.totalAssets();
    uint256 expectedAnnualFee = (totalAssets * managementFeeRate) /
      RAY;
    uint256 expectedFeeForPeriod = (expectedAnnualFee * days_) / 365;

    if (expectedFeeForPeriod > 0) {
      assertGt(feeShares, 0, "Management fees should be collected");

      uint256 feeAssets = vault.convertToAssets(feeShares);
      _assertApproxEq(
        feeAssets,
        expectedFeeForPeriod,
        "Management fee amount incorrect"
      );
    }
  }

  function test_managementFeeDoesNotReduceShareholderValue() public {
    _depositToVault(testAccount1, BASE_DEPOSIT);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialAssets = vault.convertToAssets(initialShares);

    _warpDays(30); // 30 days

    // Assets should have grown due to APR
    uint256 expectedAssets = _calculateExpectedCompoundedAssets(
      initialAssets,
      vault.yieldAPR(),
      30
    );

    vault.harvestFees();

    uint256 finalAssets = vault.convertToAssets(initialShares);

    // User should still benefit from yield growth despite management fees
    assertGt(
      finalAssets,
      initialAssets,
      "User assets should have grown"
    );

    // The growth should be close to expected (minus management fees)
    uint256 managementFeeRate = vault.managementFeeRate();
    uint256 expectedFeeReduction = (expectedAssets *
      managementFeeRate *
      30) / (RAY * 365);
    uint256 expectedNetAssets = expectedAssets - expectedFeeReduction;

    _assertApproxEq(
      finalAssets,
      expectedNetAssets,
      "Net assets after management fees incorrect"
    );
  }

  // ============ PERFORMANCE FEE TESTS ============ //

  function testFuzz_performanceFeeOnGains(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 30, 365); // Longer periods for meaningful gains

    _depositToVault(testAccount1, depositAmount);

    uint256 initialHighWaterMark = vault.highWaterMark();
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    _warpDays(days_);

    vault.harvestFees();

    uint256 finalHighWaterMark = vault.highWaterMark();
    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);

    // High water mark should increase if there were gains
    if (finalHighWaterMark > initialHighWaterMark) {
      assertGt(
        finalFeeRecipientShares,
        initialFeeRecipientShares,
        "Performance fees should be collected on gains"
      );
    }
  }

  function test_performanceFeeWatermarkPreventsDoubleFee() public {
    _depositToVault(testAccount1, BASE_DEPOSIT);

    _warpDays(30);
    vault.harvestFees();

    uint256 waterMarkAfterFirstHarvest = vault.highWaterMark();
    uint256 feeRecipientSharesAfterFirst = vault.balanceOf(
      feeRecipient
    );

    // Harvest again immediately - no additional performance fees should be collected
    vault.harvestFees();

    uint256 waterMarkAfterSecond = vault.highWaterMark();
    uint256 feeRecipientSharesAfterSecond = vault.balanceOf(
      feeRecipient
    );

    assertEq(
      waterMarkAfterSecond,
      waterMarkAfterFirstHarvest,
      "Water mark should not change on second harvest"
    );
    assertEq(
      feeRecipientSharesAfterSecond,
      feeRecipientSharesAfterFirst,
      "No additional performance fees on second harvest"
    );
  }

  function test_performanceFeeDisabledOnValueDecrease() public {
    _depositToVault(testAccount1, BASE_DEPOSIT);

    _warpDays(30);
    vault.harvestFees();

    uint256 highWaterMark = vault.highWaterMark();

    // Simulate value decrease by setting lower total assets
    uint256 reducedAssets = vault.totalAssets() / 2;
    vm.prank(globalOwner.owner());
    vault.setTotalAssets(reducedAssets);

    uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

    _warpDays(30);
    vault.harvestFees();

    uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);

    // No performance fees should be collected when below high water mark
    // (only management fees might be collected)
    uint256 performanceFeeShares = feeRecipientSharesAfter -
      feeRecipientSharesBefore;
    uint256 currentPricePerShare = vault.convertToAssets(1e18);

    if (currentPricePerShare < highWaterMark) {
      // Performance fee should be minimal or zero
      uint256 performanceFeeAssets = vault.convertToAssets(
        performanceFeeShares
      );
      assertLt(
        performanceFeeAssets,
        100 * 1e18,
        "Performance fees should be minimal when below high water mark"
      );
    }
  }

  // ============ WITHDRAWAL FEE TESTS ============ //

  function testFuzz_withdrawalFeeWithoutStakeReduction(
    uint256 depositAmount,
    uint256 withdrawalRatio
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    withdrawalRatio = bound(withdrawalRatio, 1, 100); // 1% to 100%

    _depositToVault(testAccount1, depositAmount);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 sharesToWithdraw = (shares * withdrawalRatio) / 100;
    uint256 withdrawalFeeRate = vault.withdrawalFeeRate();

    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    vm.prank(testAccount1);
    vault.redeem(sharesToWithdraw, testAccount1, testAccount1);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 feeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    // Calculate expected withdrawal fee
    uint256 expectedFeeShares = (sharesToWithdraw *
      withdrawalFeeRate) / RAY;

    _assertApproxEq(
      feeShares,
      expectedFeeShares,
      "Withdrawal fee amount incorrect"
    );
  }

  function test_noWithdrawalFeeWithStakeReduction() public {
    _depositToVault(testAccount1, BASE_DEPOSIT);

    // Give user enough stake tokens for fee reduction
    uint256 stakeRequired = vault.stakeBalanceForFeeReduction();
    deal(address(vault.stakeToken()), testAccount1, stakeRequired);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    vm.prank(testAccount1);
    vault.redeem(shares / 2, testAccount1, testAccount1);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);

    // No withdrawal fee should be collected
    assertEq(
      finalFeeRecipientShares,
      initialFeeRecipientShares,
      "No withdrawal fee should be collected with stake reduction"
    );
  }

  function testFuzz_customWithdrawalFee(
    uint256 depositAmount,
    uint256 customFeeRate
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    customFeeRate = bound(customFeeRate, 0, RAY / 10); // 0% to 10%

    // Set custom withdrawal fee for testAccount1
    vm.prank(globalOwner.owner());
    vault.setAccountWithdrawalFee(testAccount1, customFeeRate);

    _depositToVault(testAccount1, depositAmount);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    vm.prank(testAccount1);
    vault.redeem(shares / 2, testAccount1, testAccount1);

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 feeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    uint256 expectedFeeShares = ((shares / 2) * customFeeRate) / RAY;

    _assertApproxEq(
      feeShares,
      expectedFeeShares,
      "Custom withdrawal fee amount incorrect"
    );
  }

  // ============ DEPLOYMENT DELAY FEE TESTS ============ //

  function testFuzz_deploymentDelayImpact(
    uint256 depositAmount,
    uint8 deploymentDelay
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    deploymentDelay = uint8(bound(deploymentDelay, 1, 30)); // 1 to 30 days

    // Set deployment delay
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(deploymentDelay);

    uint256 sharesBefore = vault.convertToShares(depositAmount);

    _depositToVault(testAccount1, depositAmount);

    uint256 actualShares = vault.balanceOf(testAccount1);

    // With deployment delay, user should receive fewer shares
    assertLt(
      actualShares,
      sharesBefore,
      "Deployment delay should reduce shares received"
    );

    // Calculate expected maturity impact
    uint256 dailyRate = vault.yieldAPR() / 365;
    uint256 compoundFactor = RAY;
    for (uint256 i = 0; i < deploymentDelay; i++) {
      compoundFactor = (compoundFactor * (RAY + dailyRate)) / RAY;
    }
    uint256 expectedFee = (depositAmount * (compoundFactor - RAY)) /
      compoundFactor;
    uint256 expectedNetDeposit = depositAmount - expectedFee;
    uint256 expectedShares = vault.convertToShares(
      expectedNetDeposit
    );

    _assertApproxEq(
      actualShares,
      expectedShares,
      "Deployment delay impact calculation incorrect"
    );
  }

  function test_deploymentDelayVsLTokenMigration() public {
    uint256 amount = BASE_DEPOSIT;

    // Set deployment delay
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(7); // 7 days

    // Regular deposit with deployment delay
    _depositToVault(testAccount1, amount);
    uint256 sharesFromDeposit = vault.balanceOf(testAccount1);

    // L-Token migration (no deployment delay)
    lToken.mint(testAccount2, amount);
    vm.prank(testAccount2);
    lToken.approve(address(vault), amount);
    vm.prank(testAccount2);
    uint256 sharesFromMigration = vault.migrateLToken(amount);

    // Migration should give more shares than regular deposit due to no deployment delay
    assertGt(
      sharesFromMigration,
      sharesFromDeposit,
      "L-Token migration should give more shares than regular deposit"
    );
  }

  function test_instantDepositWithdrawalImpact() public {
    uint256 amount = BASE_DEPOSIT;

    // Set deployment delay
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(7);

    _depositToVault(testAccount1, amount);
    uint256 shares = vault.balanceOf(testAccount1);

    // Immediate withdrawal should work but with reduced assets due to deployment delay
    vm.prank(testAccount1);
    vault.redeem(shares, testAccount1, testAccount1);

    uint256 finalBalance = asset.balanceOf(testAccount1);
    uint256 initialBalance = INITIAL_BALANCE;
    uint256 netReceived = finalBalance - (initialBalance - amount);

    // User should receive less than deposited due to deployment delay
    assertLt(
      netReceived,
      amount,
      "Immediate withdrawal after deposit with delay should result in loss"
    );
  }

  // ============ FEE COLLECTION INTEGRATION TESTS ============ //

  function testFuzz_feeCollectionDoesNotReduceShareholderValue(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialTotalSupply = vault.totalSupply();

    _warpDays(days_);

    uint256 assetsBeforeFees = vault.convertToAssets(initialShares);

    vault.harvestFees();

    uint256 assetsAfterFees = vault.convertToAssets(initialShares);
    uint256 finalTotalSupply = vault.totalSupply();

    // User's asset value should not decrease due to fee collection
    assertGe(
      assetsAfterFees,
      assetsBeforeFees,
      "Fee collection should not reduce user asset value"
    );

    // Total supply should increase due to fee shares minted
    assertGe(
      finalTotalSupply,
      initialTotalSupply,
      "Total supply should increase from fee collection"
    );
  }

  function test_comprehensiveFeeCalculation() public {
    uint256 amount = BASE_DEPOSIT;

    _depositToVault(testAccount1, amount);
    _depositToVault(testAccount2, amount);

    uint256 initialTotalAssets = vault.totalAssets();
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    _warpDays(90); // 3 months

    vault.harvestFees();

    uint256 finalTotalAssets = vault.totalAssets();
    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 feeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    // Verify total assets grew due to APR
    assertGt(
      finalTotalAssets,
      initialTotalAssets,
      "Total assets should grow over time"
    );

    // Verify fees were collected
    assertGt(feeShares, 0, "Fees should be collected");

    // Verify fee calculation components
    uint256 managementFeeRate = vault.managementFeeRate();
    uint256 performanceFeeRate = vault.performanceFeeRate();

    assertTrue(
      managementFeeRate > 0,
      "Management fee rate should be set"
    );
    assertTrue(
      performanceFeeRate > 0,
      "Performance fee rate should be set"
    );

    // Fee assets should be reasonable proportion of total assets
    uint256 feeAssets = vault.convertToAssets(feeShares);
    uint256 feePercentage = (feeAssets * 100 * RAY) /
      finalTotalAssets;

    // Fees should be less than 10% of total assets for 3 months
    assertLt(
      feePercentage,
      10 * RAY,
      "Fees should be reasonable proportion of total assets"
    );
  }
}
