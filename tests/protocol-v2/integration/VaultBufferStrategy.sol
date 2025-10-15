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
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

/**
 * @title VaultBufferStrategy_IntegrationTest
 * @notice Integration tests for Aave buffer strategy functionality
 * @dev Tests buffer deposits, withdrawals, reward accrual, and withdrawal processing
 */
contract VaultBufferStrategy_IntegrationTest is Test, Fixtures {
  using Math for uint256;

  LedgityYieldVault public vault;
  MockLToken public lToken;
  IERC20 public asset;
  IERC20 public aToken;

  uint256 public constant BASE_AMOUNT = 10000 * 1e18; // 10k tokens
  uint256 public constant PRECISION_TOLERANCE = 1e15; // 0.1% tolerance

  function setUp() public {
    _setUp();

    // Use WETH for testing (has Aave support)
    asset = weth;
    lToken = _createLToken(asset);
    vault = _createVaultWithConfig(
      asset,
      IERC20(address(lToken)),
      true
    ); // hasAave = true

    // Get aToken address from vault
    aToken = vault.aToken();

    // Setup approvals
    _setupApprovalsForVault(vault, asset);

    // Give liquidity manager initial balance
    deal(address(asset), liquidityManager, 1_000_000 * 1e18);
    vm.prank(liquidityManager);
    asset.approve(address(vault), type(uint256).max);
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

  // ============ BUFFER DEPOSIT TESTS ============ //

  function test_depositToBuffer_investsInAave() public {
    uint256 depositAmount = BASE_AMOUNT;

    uint256 initialATokenBalance = aToken.balanceOf(address(vault));

    // Deposit to buffer
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    uint256 finalATokenBalance = aToken.balanceOf(address(vault));

    // Verify aTokens were received (invested in Aave)
    // Note: Aave may have rounding, so use approximate equality
    _assertApproxEq(
      finalATokenBalance - initialATokenBalance,
      depositAmount,
      "aToken balance should increase by deposit amount"
    );

    // Verify buffer assets reflect the deposit
    _assertApproxEq(
      vault.getBufferAssets(),
      depositAmount,
      "Buffer assets should equal deposit amount"
    );
  }

  function test_depositToBuffer_multipleDeposits() public {
    uint256 deposit1 = BASE_AMOUNT;
    uint256 deposit2 = BASE_AMOUNT * 2;

    vm.prank(liquidityManager);
    vault.depositToBuffer(deposit1);

    uint256 bufferAfterFirst = vault.getBufferAssets();

    vm.prank(liquidityManager);
    vault.depositToBuffer(deposit2);

    uint256 bufferAfterSecond = vault.getBufferAssets();

    _assertApproxEq(
      bufferAfterSecond - bufferAfterFirst,
      deposit2,
      "Second deposit should increase buffer correctly"
    );

    _assertApproxEq(
      bufferAfterSecond,
      deposit1 + deposit2,
      "Total buffer should equal sum of deposits"
    );
  }

  // ============ AAVE REWARDS TESTS ============ //

  function test_aaveRewards_accumulateOverTime() public {
    uint256 depositAmount = BASE_AMOUNT;

    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    uint256 initialBuffer = vault.getBufferAssets();

    // Warp time to accrue real Aave rewards
    _warpDays(30);

    uint256 bufferAfter30Days = vault.getBufferAssets();
    assertGt(
      bufferAfter30Days,
      initialBuffer,
      "Buffer should increase after 30 days"
    );

    // Continue accruing
    _warpDays(30);

    uint256 finalBuffer = vault.getBufferAssets();

    // Verify continued accumulation
    assertGt(
      finalBuffer,
      bufferAfter30Days,
      "Buffer should continue to accumulate rewards"
    );
  }

  // ============ BUFFER SKIM TESTS ============ //

  function test_skimBuffer_withdrawsFromAave() public {
    uint256 depositAmount = BASE_AMOUNT;
    uint256 skimAmount = BASE_AMOUNT / 2;

    // Deposit to buffer
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    uint256 initialLiquidityManagerBalance = asset.balanceOf(
      liquidityManager
    );
    uint256 initialBufferAssets = vault.getBufferAssets();

    // Skim buffer
    vm.prank(liquidityManager);
    vault.skimBuffer(skimAmount);

    uint256 finalLiquidityManagerBalance = asset.balanceOf(
      liquidityManager
    );
    uint256 finalBufferAssets = vault.getBufferAssets();

    // Verify liquidity manager received assets
    assertEq(
      finalLiquidityManagerBalance - initialLiquidityManagerBalance,
      skimAmount,
      "Liquidity manager should receive skimmed amount"
    );

    // Verify buffer decreased
    assertEq(
      (initialBufferAssets - finalBufferAssets) / 10,
      skimAmount / 10,
      "Buffer should decrease by skim amount"
    );
  }

  function test_skimBuffer_canSkimAaveRewards() public {
    uint256 depositAmount = BASE_AMOUNT;

    // Deposit to buffer
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    uint256 initialBuffer = vault.getBufferAssets();

    // Warp time to accrue real Aave rewards
    _warpDays(90);

    uint256 bufferWithRewards = vault.getBufferAssets();
    assertGt(
      bufferWithRewards,
      initialBuffer,
      "Buffer should include rewards"
    );

    uint256 rewardAmount = bufferWithRewards - initialBuffer;

    // Skim only the rewards
    vm.prank(liquidityManager);
    vault.skimBuffer(rewardAmount);

    uint256 finalBuffer = vault.getBufferAssets();

    _assertApproxEq(
      finalBuffer,
      initialBuffer,
      "After skimming rewards, buffer should equal original deposit"
    );
  }

  // ============ WITHDRAWAL REQUEST PROCESSING TESTS ============ //

  function test_processRequests_withdrawsFromAaveBuffer() public {
    uint256 depositAmount = BASE_AMOUNT;

    // User deposits to vault
    _depositToVault(testAccount1, depositAmount);

    // User requests withdrawal
    uint256 shares = vault.balanceOf(testAccount1);
    uint256 gasFee = vault.withdrawalGasFee();

    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: gasFee }(shares / 2);

    // Deposit to buffer to cover withdrawal
    vm.prank(liquidityManager);
    vault.depositToBuffer(depositAmount);

    uint256 initialBufferAssets = vault.getBufferAssets();
    uint256 initialUserBalance = asset.balanceOf(testAccount1);

    // Process withdrawal request
    uint256[] memory requestIds = new uint256[](1);
    requestIds[0] = 0;

    vm.prank(liquidityManager);
    vault.processRequests(requestIds, 0);

    uint256 finalBufferAssets = vault.getBufferAssets();
    uint256 finalUserBalance = asset.balanceOf(testAccount1);

    // Verify user received assets
    assertGt(
      finalUserBalance,
      initialUserBalance,
      "User should receive withdrawn assets"
    );

    // Verify buffer decreased by withdrawal amount
    uint256 actualWithdrawn = finalUserBalance - initialUserBalance;
    assertApproxEqAbs(
      initialBufferAssets - finalBufferAssets,
      actualWithdrawn,
      1e15, // 0.001 tolerance for rounding
      "Buffer should decrease by withdrawal amount"
    );
  }

  function test_processRequests_usesAddedLiquidityWhenBufferInsufficient()
    public
  {
    uint256 depositAmount = BASE_AMOUNT;

    // User deposits to vault
    _depositToVault(testAccount1, depositAmount);

    // User requests withdrawal
    uint256 shares = vault.balanceOf(testAccount1);
    uint256 gasFee = vault.withdrawalGasFee();

    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: gasFee }(shares);

    // Get withdrawal request details
    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);
    uint256 requestAmount = requests[0].amount;

    // Deposit small amount to buffer (insufficient)
    uint256 smallBufferAmount = depositAmount / 4;
    vm.prank(liquidityManager);
    vault.depositToBuffer(smallBufferAmount);

    // Calculate additional liquidity needed
    uint256 addedLiquidity = requestAmount - smallBufferAmount;

    uint256 initialUserBalance = asset.balanceOf(testAccount1);

    // Process with added liquidity
    uint256[] memory requestIds = new uint256[](1);
    requestIds[0] = 0;

    vm.prank(liquidityManager);
    vault.processRequests(requestIds, addedLiquidity);

    uint256 finalUserBalance = asset.balanceOf(testAccount1);

    // Verify user received full withdrawal amount
    assertApproxEqAbs(
      finalUserBalance - initialUserBalance,
      requestAmount,
      1e15,
      "User should receive full withdrawal amount"
    );
  }

  function test_processRequests_revertsWhenInsufficientLiquidity()
    public
  {
    uint256 depositAmount = BASE_AMOUNT;

    // User deposits to vault
    _depositToVault(testAccount1, depositAmount);

    // User requests withdrawal
    uint256 shares = vault.balanceOf(testAccount1);
    uint256 gasFee = vault.withdrawalGasFee();

    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: gasFee }(shares);

    // Don't add any liquidity to buffer

    uint256[] memory requestIds = new uint256[](1);
    requestIds[0] = 0;

    // Should revert due to insufficient liquidity
    vm.prank(liquidityManager);
    vm.expectRevert(LedgityYieldVault.InsufficientLiquidity.selector);
    vault.processRequests(requestIds, 0);
  }

  function test_processRequests_handlesMultipleRequestsWithAaveBuffer()
    public
  {
    uint256 depositAmount = BASE_AMOUNT;

    address[] memory users = new address[](3);
    users[0] = testAccount1;
    users[1] = testAccount2;
    users[2] = testAccount3;

    // All users request withdrawals
    uint256 gasFee = vault.withdrawalGasFee();

    // Multiple users deposit
    for (uint256 i = 0; i < users.length; i++) {
      address user = users[i];
      _depositToVault(user, depositAmount);

      uint256 balance = vault.balanceOf(user);

      vm.prank(user);
      vault.requestWithdrawal{ value: gasFee }(balance / 2);
    }

    // Get total withdrawal amount needed
    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);
    uint256 totalWithdrawalAmount = requests[0].amount +
      requests[1].amount +
      requests[2].amount;

    // Deposit enough to buffer to cover all withdrawals
    vm.prank(liquidityManager);
    vault.depositToBuffer(totalWithdrawalAmount);

    uint256 initialBuffer = vault.getBufferAssets();

    // Process all requests
    uint256[] memory requestIds = new uint256[](3);
    requestIds[0] = 0;
    requestIds[1] = 1;
    requestIds[2] = 2;

    vm.prank(liquidityManager);
    vault.processRequests(requestIds, 0);

    uint256 finalBuffer = vault.getBufferAssets();

    // Verify all requests were processed
    ILedgityDataProvider.WithdrawalRequestRead[]
      memory allRequests = vault.getWithdrawalRequests(false, 0);

    for (uint256 i = 0; i < 3; i++) {
      assertTrue(
        allRequests[i].processed,
        "Request should be marked as processed"
      );
    }

    // Verify buffer decreased appropriately
    assertLt(
      finalBuffer,
      initialBuffer,
      "Buffer should decrease after processing withdrawals"
    );
  }
}
