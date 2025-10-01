// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
import { StdInvariant } from "foundry/lib/forge-std/src/StdInvariant.sol";
import { StdUtils } from "foundry/lib/forge-std/src/StdUtils.sol";
import { Vm } from "foundry/lib/forge-std/src/Vm.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Vault_InvariantsTest
 * @notice Core invariant tests for LedgityYieldVault protocol state integrity
 * @dev Tests fundamental protocol invariants that must ALWAYS hold
 */
contract Vault_InvariantsTest is StdInvariant, Test, Fixtures {
  // Test vault and handler
  LedgityYieldVault public vault;
  VaultHandler public handler;

  // Test assets
  IERC20 public asset;
  MockLToken public lToken;

  // Configuration
  uint256 public constant INITIAL_VAULT_ASSETS = 1000000 * 1e18; // 1M tokens

  function setUp() public {
    _setUp();

    asset = usdc;
    lToken = _createLToken(asset);
    vault = _createVault(asset, IERC20(address(lToken)));

    // Setup initial vault state
    deal(address(asset), address(this), INITIAL_VAULT_ASSETS);
    asset.approve(address(vault), INITIAL_VAULT_ASSETS);
    vault.deposit(INITIAL_VAULT_ASSETS, address(this));

    // Create handler with test users
    handler = new VaultHandler(vault, asset);

    // Set handler as target for invariant testing
    targetContract(address(handler));
  }

  // ======== ACCOUNTING INVARIANTS ======== //

  /**
   * @notice INV-1: Total assets must always be >= sum of all shares value
   * @dev This ensures no value is created from thin air
   */
  function invariant_totalAssets_gte_sharesValue() public view {
    uint256 totalAssets = vault.totalAssets();
    uint256 totalSupply = vault.totalSupply();

    if (totalSupply > 0) {
      uint256 sharesValue = vault.convertToAssets(totalSupply);
      assertGe(
        totalAssets,
        sharesValue,
        "INV-1: Total assets < shares value"
      );
    }
  }

  /**
   * @notice INV-2: Buffer assets must never exceed total vault assets
   * @dev Buffer is a subset of total assets
   */
  function invariant_buffer_lte_totalAssets() public view {
    uint256 bufferAssets = vault.getBufferAssets();
    uint256 totalAssets = vault.totalAssets();

    assertLe(
      bufferAssets,
      totalAssets,
      "INV-2: Buffer exceeds total assets"
    );
  }

  /**
   * @notice INV-3: Share price should never decrease (except for fees/losses)
   * @dev Tracks high water mark to ensure yield accrual
   */
  function invariant_sharePrice_neverDecreases() public view {
    uint256 currentPrice = handler.ghost_currentSharePrice();
    uint256 highWaterMark = handler.ghost_highWaterMarkPrice();

    // Allow small rounding errors (0.01%)
    uint256 tolerance = highWaterMark / 10000;

    assertGe(
      currentPrice + tolerance,
      highWaterMark,
      "INV-3: Share price decreased significantly"
    );
  }

  /**
   * @notice INV-4: Total supply should match sum of all balances
   * @dev Basic ERC20 accounting invariant
   */
  function invariant_totalSupply_eq_sumBalances() public view {
    uint256 totalSupply = vault.totalSupply();
    uint256 sumBalances = vault.balanceOf(address(this)) +
      vault.balanceOf(testAccount1) +
      vault.balanceOf(testAccount2) +
      vault.balanceOf(testAccount3) +
      vault.balanceOf(liquidityManager) +
      vault.balanceOf(address(handler));

    assertEq(
      totalSupply,
      sumBalances,
      "INV-4: Total supply != sum of balances"
    );
  }

  // ======== LIQUIDITY INVARIANTS ======== //

  /**
   * @notice INV-5: If shares exist, assets must exist
   * @dev Prevents share dilution to zero
   */
  function invariant_shares_imply_assets() public view {
    uint256 totalSupply = vault.totalSupply();
    uint256 totalAssets = vault.totalAssets();

    if (totalSupply > 0) {
      assertGt(totalAssets, 0, "INV-5: Shares exist but no assets");
    }
  }

  /**
   * @notice INV-6: Buffer should match actual vault balance
   * @dev Ensures buffer accounting is accurate
   */
  function invariant_buffer_eq_actualBalance() public view {
    uint256 bufferAssets = vault.getBufferAssets();
    uint256 actualBalance = asset.balanceOf(address(vault));

    // If no Aave strategy, buffer should equal balance
    if (!vault.hasBufferStrategy()) {
      assertEq(
        bufferAssets,
        actualBalance,
        "INV-6: Buffer != actual balance"
      );
    }
  }

  // ======== FEE INVARIANTS ======== //

  /**
   * @notice INV-7: High water mark should never decrease
   * @dev Prevents double-charging performance fees
   */
  function invariant_highWaterMark_neverDecreases() public view {
    uint256 currentHWM = vault.highWaterMark();
    uint256 trackedHWM = handler.ghost_highWaterMark();

    assertGe(
      currentHWM,
      trackedHWM,
      "INV-7: High water mark decreased"
    );
  }

  /**
   * @notice INV-8: Fee time should only move forward
   * @dev Ensures fees are calculated correctly
   */
  function invariant_feeTime_onlyIncreases() public view {
    uint256 lastFeeTime = vault.lastFeeTime();
    uint256 trackedFeeTime = handler.ghost_lastFeeTime();

    assertGe(
      lastFeeTime,
      trackedFeeTime,
      "INV-8: Fee time moved backward"
    );
  }

  // ======== YIELD INVARIANTS ======== //

  /**
   * @notice INV-9: Compound time should only move forward
   * @dev Ensures yield calculations are monotonic
   */
  function invariant_compoundTime_onlyIncreases() public view {
    uint256 lastCompoundTime = vault.lastCompoundTime();
    uint256 trackedCompoundTime = handler.ghost_lastCompoundTime();

    assertGe(
      lastCompoundTime,
      trackedCompoundTime,
      "INV-9: Compound time moved backward"
    );
  }

  /**
   * @notice INV-10: Total assets should grow with time (if APR > 0)
   * @dev Validates yield accrual logic
   */
  function invariant_assets_growWithYield() public view {
    uint256 currentAssets = vault.totalAssets();
    uint256 initialAssets = handler.ghost_initialAssets();
    uint256 netDeposits = handler.ghost_totalDeposits();
    uint256 netWithdrawals = handler.ghost_totalWithdrawals();

    // Expected minimum assets = initial + deposits - withdrawals
    uint256 expectedMinAssets = initialAssets +
      netDeposits -
      netWithdrawals;

    // Current assets should be >= expected (due to yield)
    // Allow small tolerance for rounding
    uint256 tolerance = expectedMinAssets / 10000; // 0.01%

    assertGe(
      currentAssets + tolerance,
      expectedMinAssets,
      "INV-10: Assets below expected minimum"
    );
  }

  // ======== GHOST VARIABLE INVARIANTS ======== //

  /**
   * @notice INV-11: Ghost deposit tracking should be consistent
   * @dev Validates handler accounting
   */
  function invariant_ghost_depositConsistency() public view {
    uint256 totalDeposits = handler.ghost_totalDeposits();
    uint256 depositCount = handler.ghost_depositCount();

    // If deposits occurred, total should be positive
    if (depositCount > 0) {
      assertGt(
        totalDeposits,
        0,
        "INV-11: Deposits occurred but total is zero"
      );
    }
  }

  /**
   * @notice INV-12: Ghost withdrawal tracking should be consistent
   * @dev Validates handler accounting
   */
  function invariant_ghost_withdrawalConsistency() public view {
    uint256 totalWithdrawals = handler.ghost_totalWithdrawals();
    uint256 withdrawalCount = handler.ghost_withdrawalCount();

    // If withdrawals occurred, total should be positive
    if (withdrawalCount > 0) {
      assertGt(
        totalWithdrawals,
        0,
        "INV-12: Withdrawals occurred but total is zero"
      );
    }
  }

  // ======== SOLVENCY INVARIANTS ======== //

  /**
   * @notice INV-13: Vault should always be able to redeem at least 1 share
   * @dev Ensures vault remains solvent
   */
  function invariant_vault_canRedeemShares() public view {
    uint256 totalSupply = vault.totalSupply();

    if (totalSupply > 0) {
      uint256 redeemValue = vault.convertToAssets(1e18);
      assertGt(redeemValue, 0, "INV-13: Cannot redeem shares");
    }
  }

  /**
   * @notice INV-14: Conversion functions should be consistent
   * @dev convertToShares(convertToAssets(x)) should ≈ x
   */
  function invariant_conversion_consistency() public view {
    uint256 testShares = 1000 * 1e18;
    uint256 totalSupply = vault.totalSupply();

    if (totalSupply > testShares) {
      uint256 assets = vault.convertToAssets(testShares);
      uint256 sharesBack = vault.convertToShares(assets);

      // Allow 0.1% tolerance for rounding
      uint256 tolerance = testShares / 1000;

      assertApproxEqAbs(
        sharesBack,
        testShares,
        tolerance,
        "INV-14: Conversion inconsistency"
      );
    }
  }
}

/**
 * @title VaultHandler
 * @notice Handler contract for vault operations with ghost variable tracking
 * @dev Manages realistic vault interactions and tracks state for invariant validation
 */
contract VaultHandler is Test, Fixtures {
  // Core contracts
  LedgityYieldVault public immutable vault;
  IERC20 public immutable asset;

  // Ghost variables - Accounting
  uint256 public ghost_totalDeposits;
  uint256 public ghost_totalWithdrawals;
  uint256 public ghost_depositCount;
  uint256 public ghost_withdrawalCount;
  uint256 public ghost_initialAssets;

  // Ghost variables - Price tracking
  uint256 public ghost_currentSharePrice;
  uint256 public ghost_highWaterMarkPrice;

  // Ghost variables - Time tracking
  uint256 public ghost_lastFeeTime;
  uint256 public ghost_lastCompoundTime;
  uint256 public ghost_highWaterMark;

  // Configuration
  uint256 public constant MAX_DEPOSIT = 100000 * 1e18;
  uint256 public constant MIN_DEPOSIT = 1 * 1e18;
  uint256 public constant MAX_TIME_WARP = 30 days;

  constructor(LedgityYieldVault _vault, IERC20 _asset) {
    vault = _vault;
    asset = _asset;

    // Initialize ghost variables
    ghost_initialAssets = _vault.totalAssets();
    ghost_currentSharePrice = _getSharePrice();
    ghost_highWaterMarkPrice = ghost_currentSharePrice;
    ghost_lastFeeTime = _vault.lastFeeTime();
    ghost_lastCompoundTime = _vault.lastCompoundTime();
    ghost_highWaterMark = _vault.highWaterMark();
  }

  // ======== HELPER FUNCTIONS ======== //

  function _getSharePrice() internal view returns (uint256) {
    uint256 totalSupply = vault.totalSupply();
    if (totalSupply == 0) return 1e18;
    return vault.convertToAssets(1e18);
  }

  function _updateGhostPriceTracking() internal {
    uint256 currentPrice = _getSharePrice();
    ghost_currentSharePrice = currentPrice;
    if (currentPrice > ghost_highWaterMarkPrice) {
      ghost_highWaterMarkPrice = currentPrice;
    }
  }

  function _updateGhostTimeTracking() internal {
    uint256 currentFeeTime = vault.lastFeeTime();
    uint256 currentCompoundTime = vault.lastCompoundTime();
    uint256 currentHWM = vault.highWaterMark();

    if (currentFeeTime > ghost_lastFeeTime) {
      ghost_lastFeeTime = currentFeeTime;
    }
    if (currentCompoundTime > ghost_lastCompoundTime) {
      ghost_lastCompoundTime = currentCompoundTime;
    }
    if (currentHWM > ghost_highWaterMark) {
      ghost_highWaterMark = currentHWM;
    }
  }

  function _randomActor(
    uint256 seed
  ) internal view returns (address) {
    return users[seed % users.length];
  }

  // ======== VAULT OPERATIONS ======== //

  /**
   * @notice User deposits assets into vault
   * @param actorSeed Seed to select random actor
   * @param amount Raw fuzzed deposit amount
   */
  function deposit(uint256 actorSeed, uint256 amount) external {
    address actor = _randomActor(actorSeed);
    amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

    // Give actor assets
    deal(address(asset), actor, amount);

    // Perform deposit
    vm.startPrank(actor);
    asset.approve(address(vault), amount);
    vault.deposit(amount, actor);
    vm.stopPrank();

    // Update ghost variables
    ghost_totalDeposits += amount;
    ghost_depositCount++;
    _updateGhostPriceTracking();
    _updateGhostTimeTracking();
  }

  /**
   * @notice User withdraws assets from vault
   * @param actorSeed Seed to select random actor
   * @param sharesPct Percentage of shares to withdraw (0-100)
   */
  function withdraw(uint256 actorSeed, uint256 sharesPct) external {
    address actor = _randomActor(actorSeed);
    uint256 balance = vault.balanceOf(actor);

    // Skip if no balance
    if (balance == 0) return;

    // Withdraw percentage of balance (1-100%)
    sharesPct = bound(sharesPct, 1, 100);
    uint256 shares = (balance * sharesPct) / 100;
    if (shares == 0) return;

    // Check buffer has enough liquidity
    uint256 expectedAssets = vault.convertToAssets(shares);
    uint256 bufferAssets = vault.getBufferAssets();
    if (bufferAssets < expectedAssets) return;

    // Perform withdrawal
    vm.startPrank(actor);
    uint256 assets = vault.redeem(shares, actor, actor);
    vm.stopPrank();

    // Update ghost variables
    ghost_totalWithdrawals += assets;
    ghost_withdrawalCount++;
    _updateGhostPriceTracking();
    _updateGhostTimeTracking();
  }

  /**
   * @notice Liquidity manager deposits to buffer
   * @param amount Raw fuzzed amount
   */
  function depositToBuffer(uint256 amount) external {
    amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

    // Give liquidity manager assets
    deal(address(asset), liquidityManager, amount);

    // Perform buffer deposit
    vm.startPrank(liquidityManager);
    asset.approve(address(vault), amount);
    vault.depositToBuffer(amount);
    vm.stopPrank();

    _updateGhostTimeTracking();
  }

  /**
   * @notice Liquidity manager skims from buffer
   * @param amount Raw fuzzed amount
   */
  function skimBuffer(uint256 amount) external {
    uint256 bufferAssets = vault.getBufferAssets();
    if (bufferAssets == 0) return;

    amount = bound(amount, MIN_DEPOSIT, bufferAssets);

    // Perform buffer skim
    vm.startPrank(liquidityManager);
    vault.skimBuffer(amount);
    vm.stopPrank();

    _updateGhostTimeTracking();
  }

  /**
   * @notice Harvest fees
   */
  function harvestFees() external {
    vault.harvestFees();
    _updateGhostPriceTracking();
    _updateGhostTimeTracking();
  }

  /**
   * @notice Warp time forward
   * @param timeJump Raw fuzzed time jump
   */
  function warpTime(uint256 timeJump) external {
    timeJump = bound(timeJump, 1 hours, MAX_TIME_WARP);
    vm.warp(block.timestamp + timeJump);
    _updateGhostPriceTracking();
  }
}
