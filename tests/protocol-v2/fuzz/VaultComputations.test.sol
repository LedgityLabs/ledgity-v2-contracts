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

  function _calculateExpectedFeeShares(
    uint256 currentAssets,
    uint256 totalSupply,
    uint256 timeElapsed,
    uint256 managementFeeRate,
    uint256 performanceFeeRate,
    uint256 highWaterMark
  ) internal view returns (uint256) {
    uint256 decimalsOffset = 1;

    uint256 annualManagementFees = (currentAssets *
      managementFeeRate) / RAY;
    uint256 managementFeeAssets = (annualManagementFees *
      timeElapsed) / 365 days;

    uint256 sharesDenominator = totalSupply + decimalsOffset;
    if (sharesDenominator == 0) sharesDenominator = 1;

    uint256 pricePerShareBeforePerfFee = (10 ** vault.decimals() *
      ((currentAssets + 1) - managementFeeAssets)) /
      sharesDenominator;

    uint256 performanceFeeAssets = 0;
    if (highWaterMark < pricePerShareBeforePerfFee) {
      uint256 profitPerShare = pricePerShareBeforePerfFee -
        highWaterMark;
      uint256 profit = (profitPerShare * totalSupply) /
        (10 ** vault.decimals());
      performanceFeeAssets = (profit * performanceFeeRate) / RAY;
    }

    uint256 totalFeeAssets = managementFeeAssets +
      performanceFeeAssets;
    return
      (totalFeeAssets * (totalSupply + decimalsOffset)) /
      ((currentAssets - totalFeeAssets) + 1);
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

  function testFuzz_bufferRewardsDoNotAffectShareValue(
    uint256 depositAmount,
    uint256 bufferRewards
  ) public {
    if (!vault.hasBufferStrategy()) return;

    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    bufferRewards = bound(bufferRewards, 1e18, 10_000 * 1e18);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialPricePerShare = vault.convertToAssets(1e18);

    // Simulate buffer earning rewards by manually adding assets to buffer
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
    uint256 lastFeeTime = vault.lastFeeTime();
    uint256 totalSupplyBefore = vault.totalSupply();

    _warpDays(days_);

    uint256 currentAssetsBefore = vault.totalAssets();
    uint256 timeElapsed = block.timestamp - lastFeeTime;

    vault.harvestFees();

    uint256 finalFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 feeShares = finalFeeRecipientShares -
      initialFeeRecipientShares;

    if (feeShares > 0) {
      uint256 expectedFeeShares = _calculateExpectedFeeShares(
        currentAssetsBefore,
        totalSupplyBefore,
        timeElapsed,
        managementFeeRate,
        vault.performanceFeeRate(),
        vault.highWaterMark()
      );

      uint256 feeAssets = vault.convertToAssets(feeShares);
      uint256 expectedFeeAssetsValue = vault.convertToAssets(
        expectedFeeShares
      );

      _assertApproxEq(
        feeAssets,
        expectedFeeAssetsValue,
        "Total fee amount incorrect"
      );
    }
  }

  function testFuzz_managementFeeDoesNotReduceShareholderValue(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialAssets = vault.convertToAssets(initialShares);

    _warpDays(days_);

    vault.harvestFees();

    uint256 finalAssets = vault.convertToAssets(initialShares);

    // User should still benefit from yield growth despite management fees
    assertGt(
      finalAssets,
      initialAssets,
      "User assets should have grown"
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

  function testFuzz_performanceFeeWatermarkPreventsDoubleFee(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    _warpDays(days_);
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

  function testFuzz_performanceFeeDisabledOnValueDecrease(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    _warpDays(days_);
    vault.harvestFees();

    uint256 highWaterMark = vault.highWaterMark();
    uint256 lastFeeTime = vault.lastFeeTime();

    // Simulate value decrease by setting lower total assets
    vm.prank(globalOwner.owner());
    vault.setTotalAssets(vault.totalAssets() / 2);

    uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);
    uint256 totalSupplyBefore = vault.totalSupply();

    _warpDays(days_);

    uint256 currentAssetsBefore = vault.totalAssets();

    vault.harvestFees();

    uint256 feeSharesCollected = vault.balanceOf(feeRecipient) -
      feeRecipientSharesBefore;
    uint256 currentPricePerShare = vault.convertToAssets(1e18);

    // When below high water mark, only management fees should be collected
    if (currentPricePerShare < highWaterMark) {
      uint256 expectedFeeShares = _calculateExpectedFeeShares(
        currentAssetsBefore,
        totalSupplyBefore,
        block.timestamp - lastFeeTime,
        vault.managementFeeRate(),
        vault.performanceFeeRate(),
        highWaterMark
      );

      uint256 feeAssetsCollected = vault.convertToAssets(
        feeSharesCollected
      );
      uint256 expectedFeeAssets = vault.convertToAssets(
        expectedFeeShares
      );

      // Verify only management fees were collected (with tolerance)
      _assertApproxEq(
        feeAssetsCollected,
        expectedFeeAssets,
        "Only management fees should be collected when below high water mark"
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

    deal(address(asset), liquidityManager, depositAmount);
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

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

  function testFuzz_noWithdrawalFeeWithStakeReduction(
    uint256 depositAmount,
    uint256 withdrawalRatio
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    withdrawalRatio = bound(withdrawalRatio, 1, 100); // 1% to 100%

    _depositToVault(testAccount1, depositAmount);

    // Give user enough stake tokens for fee reduction
    uint256 stakeRequired = vault.stakeBalanceForFeeReduction();
    deal(address(vault.stakeToken()), testAccount1, stakeRequired);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 sharesToWithdraw = (shares * withdrawalRatio) / 100;
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    deal(address(asset), liquidityManager, depositAmount);
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    vm.prank(testAccount1);
    vault.redeem(sharesToWithdraw, testAccount1, testAccount1);

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
    customFeeRate = bound(customFeeRate, RAY / 10_000_000, RAY / 10); // 0.00000001% to 10%

    // Set custom withdrawal fee for testAccount1
    vm.prank(globalOwner.owner());
    vault.setAccountWithdrawalFee(testAccount1, customFeeRate);

    _depositToVault(testAccount1, depositAmount);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);

    deal(address(asset), liquidityManager, depositAmount);
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

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

  function testFuzz_deploymentDelayVsLTokenMigration(
    uint256 depositAmount,
    uint8 deploymentDelay
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    deploymentDelay = uint8(bound(deploymentDelay, 1, 30)); // 1 to 30 days

    // Set deployment delay
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(deploymentDelay);

    // Regular deposit with deployment delay
    _depositToVault(testAccount1, depositAmount);
    uint256 sharesFromDeposit = vault.balanceOf(testAccount1);

    // L-Token migration (no deployment delay)
    lToken.mint(testAccount2, depositAmount);
    vm.prank(testAccount2);
    lToken.approve(address(vault), depositAmount);
    vm.prank(testAccount2);
    uint256 sharesFromMigration = vault.migrateLToken(depositAmount);

    // Migration should give more shares than regular deposit due to no deployment delay
    assertGt(
      sharesFromMigration,
      sharesFromDeposit,
      "L-Token migration should give more shares than regular deposit"
    );
  }

  function testFuzz_instantDepositWithdrawalImpact(
    uint256 depositAmount,
    uint8 deploymentDelay
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    deploymentDelay = uint8(bound(deploymentDelay, 1, 30)); // 1 to 30 days

    // Set deployment delay
    vm.prank(globalOwner.owner());
    vault.updateDeploymentDelay(deploymentDelay);

    _depositToVault(testAccount1, depositAmount);
    uint256 shares = vault.balanceOf(testAccount1);

    deal(address(asset), liquidityManager, depositAmount);
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    // Immediate withdrawal should work but with reduced assets due to deployment delay
    vm.prank(testAccount1);
    vault.redeem(shares, testAccount1, testAccount1);

    uint256 finalBalance = asset.balanceOf(testAccount1);
    uint256 initialBalance = INITIAL_BALANCE;
    uint256 netReceived = finalBalance -
      (initialBalance - depositAmount);

    // User should receive less than deposited due to deployment delay
    assertLt(
      netReceived,
      depositAmount,
      "Immediate withdrawal after deposit with delay should result in loss"
    );
  }

  // ============ FEE COLLECTION INTEGRATION TESTS ============ //

  function testFuzz_feeCollectionDilutesShareValue(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 1, 365);

    _depositToVault(testAccount1, depositAmount);

    uint256 initialShares = vault.balanceOf(testAccount1);
    uint256 initialAssets = vault.convertToAssets(initialShares);
    uint256 initialTotalSupply = vault.totalSupply();

    _warpDays(days_);

    vault.harvestFees();

    uint256 finalAssets = vault.convertToAssets(initialShares);
    uint256 finalTotalSupply = vault.totalSupply();

    // User's shares should still have grown due to yield
    assertGt(
      finalAssets,
      initialAssets,
      "User assets should have grown despite fee dilution"
    );

    // Total supply should increase due to fee shares minted
    assertGt(
      finalTotalSupply,
      initialTotalSupply,
      "Total supply should increase from fee collection"
    );
  }

  function testFuzz_comprehensiveFeeCalculation(
    uint256 depositAmount,
    uint256 days_
  ) public {
    depositAmount = bound(depositAmount, 1e18, 100_000 * 1e18);
    days_ = bound(days_, 30, 365); // 30 days to 1 year for meaningful fee collection

    _depositToVault(testAccount1, depositAmount);
    _depositToVault(testAccount2, depositAmount);

    uint256 initialTotalAssets = vault.totalAssets();
    uint256 initialFeeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 lastFeeTime = vault.lastFeeTime();
    uint256 totalSupplyBefore = vault.totalSupply();

    _warpDays(days_);

    uint256 currentAssetsBefore = vault.totalAssets();
    uint256 timeElapsed = block.timestamp - lastFeeTime;

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

    // Calculate expected fees using exact formula from _computeFeeData
    uint256 expectedFeeShares = _calculateExpectedFeeShares(
      currentAssetsBefore,
      totalSupplyBefore,
      timeElapsed,
      vault.managementFeeRate(),
      vault.performanceFeeRate(),
      vault.highWaterMark()
    );

    uint256 actualFeeAssets = vault.convertToAssets(feeShares);
    uint256 expectedFeeAssetsValue = vault.convertToAssets(
      expectedFeeShares
    );

    _assertApproxEq(
      actualFeeAssets,
      expectedFeeAssetsValue,
      "Total fee calculation incorrect"
    );
  }
}
