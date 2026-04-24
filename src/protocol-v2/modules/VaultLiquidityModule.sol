// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// Library
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// Interface
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";

/**
 * @title VaultLiquidityModule
 * @notice Abstract contract that extends ERC4626 to handle liquidity, APR and fee calculations for vaults
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
abstract contract VaultLiquidityModule is
  IVaultLiquidityModule,
  ERC4626Upgradeable,
  OwnableUpgradeable
{
  /** ======== LIBRARIES ======== */

  using Math for uint256;

  /** ======== ERRORS ======== */

  error RateAboveHundredPercent();

  /** ======== STORAGE ======== */

  // Base rate constant representing 100%
  uint256 public constant RAY = 1e27;

  // Decimal offset for virtual shares (18 - asset decimals), cached at initialization
  uint8 public decimalsOffset;

  // Total assets under management
  uint256 private _totalAssets;

  // Last timestamp when assets were compounded (only full compounding periods)
  uint256 public lastCompoundTime;
  // The timestamp of the last fee calculation, used to compute management fees
  uint256 public lastFeeTime;
  // The highest price per share ever reached, performance fees are taken when
  // the price per share is above this value, always express in 18 decimals
  uint256 public highWaterMark;

  // Deployment delay period in days for calculating deposit fees (max 255 days)
  uint8 public deploymentDelay;

  // Annual Percentage Rate in RAY
  uint256 public yieldAPR;

  // Management fee in RAY
  uint256 public managementFeeRate;
  // Performance fee in RAY
  uint256 public performanceFeeRate;
  // Withdrawal fee in RAY
  uint256 public withdrawalFeeRate;
  // Required amount of msg.value attached to withdrawal requests
  uint256 public withdrawalGasFee;

  // Custom fee structures for specific accounts
  mapping(address => uint256) public accountWithdrawalFee;

  /** ======== INITIALIZER ======== */

  /**
   * @notice Initializes the VaultLiquidityModule with fee rates and APR
   * @param params The initialization parameters
   * @param asset The underlying asset
   */
  function __VaultLiquidityModule_init(
    VaultLiquidityInitParams memory params,
    address asset
  ) internal {
    __ERC4626_init(ERC20Upgradeable(asset));

    // Cache decimal offset to avoid repeated calculations
    decimalsOffset = uint8(18 - ERC20Upgradeable(asset).decimals());

    // Initialize high water mark at 1 share = 1 asset if not specified
    highWaterMark = params.highWaterMark != 0
      ? params.highWaterMark
      : 10 ** (18 - decimalsOffset);
    // Set initial virtual reserves for predefined share price (cross-chain alignment)
    // Creates 1 virtual share at specified price, locks it permanently
    if (params.initialAssetsPerShare != 0) {
      _totalAssets = params.initialAssetsPerShare; // e.g., 1.05e6 assets
      _mint(address(0xdead), 1e18); // 1 share at that price
    }

    deploymentDelay = params.deploymentDelay;
    yieldAPR = params.yieldAPR;

    managementFeeRate = params.managementFeeRate;
    performanceFeeRate = params.performanceFeeRate;
    withdrawalFeeRate = params.withdrawalFeeRate;
    withdrawalGasFee = params.withdrawalGasFee;

    // Align to next UTC day boundary for cross-chain synchronization
    // Rewards start next full day - safer and simpler than crediting partial days
    lastCompoundTime = ((block.timestamp / 1 days) + 1) * 1 days;
    // Fees accrue from actual deployment time (not aligned to day boundary)
    lastFeeTime = block.timestamp;
  }

  /** ======== OVERRIDES ======== */

  /**
   * @dev Get total assets for share calculations
   * @return currentTotalAssets Total assets available for share price calculations
   */
  function totalAssets()
    public
    view
    override(ERC4626Upgradeable, IVaultLiquidityModule)
    returns (uint256 currentTotalAssets)
  {
    currentTotalAssets = _totalAssets;

    /// @dev Edge case before start of first compound period at vault initialization
    if (block.timestamp < lastCompoundTime) return currentTotalAssets;

    // Time elapsed since last compound
    uint256 timeElapsed = block.timestamp - lastCompoundTime;
    // Calculate number of full days elapsed
    uint256 fullDays = timeElapsed / 1 days;

    if (0 < fullDays) {
      // Daily rate = APR / 365
      uint256 dailyRate = yieldAPR / 365;

      // Apply daily compounding for full days only
      for (uint256 i; i < fullDays; i++) {
        currentTotalAssets = currentTotalAssets.mulDiv(
          RAY + dailyRate,
          RAY
        );
      }
    }

    return currentTotalAssets;
  }

  /**
   * @notice Converts an amount of assets (underlying) to shares (shares tokens)
   * @param assets The amount of underlying assets to convert
   * @return shares The amount of shares (shares tokens) equivalent to the given assets
   */
  function convertToShares(
    uint256 assets
  )
    public
    view
    override(ERC4626Upgradeable, IVaultLiquidityModule)
    returns (uint256 shares)
  {
    uint256 supply = totalSupply();
    uint256 currentAssets = totalAssets();

    (uint256 feeShares, ) = getFeeData();

    shares = assets.mulDiv(
      supply + feeShares + (10 ** decimalsOffset),
      currentAssets + 1
    );
  }

  /**
   * @notice Converts an amount of shares (shares tokens) to assets (underlying)
   * @param shares The amount of shares (shares tokens) to convert
   * @return assets The amount of underlying assets equivalent to the given shares
   */
  function convertToAssets(
    uint256 shares
  )
    public
    view
    override(ERC4626Upgradeable, IVaultLiquidityModule)
    returns (uint256 assets)
  {
    uint256 supply = totalSupply();
    uint256 currentAssets = totalAssets();

    (uint256 feeShares, ) = getFeeData();

    assets = shares.mulDiv(
      currentAssets + 1,
      supply + feeShares + (10 ** decimalsOffset)
    );
  }

  /** ======== INTERNAL VIEWS ======== */

  /**
   * @dev Calculate deposit fee based on deployment delay
   * Fee represents the yield needed to compound back to original deposit amount
   * @param assets The amount of assets being deposited
   * @return fee The amount of yield to be deducted from shares
   */
  function _computeMaturityImpact(
    uint256 assets
  ) internal view returns (uint256 fee) {
    if (deploymentDelay == 0) return 0;

    // Calculate compound factor for deployment delay period
    uint256 dailyRate = yieldAPR / 365;

    // Calculate: (1 + dailyRate)^deploymentDelay
    uint256 compoundFactor = RAY;
    for (uint256 i; i < deploymentDelay; i++) {
      compoundFactor = compoundFactor.mulDiv(RAY + dailyRate, RAY);
    }

    // Fee = assets * ((1 + rate)^delay - 1) / (1 + rate)^delay
    // This ensures: (assets - fee) * (1 + rate)^delay = assets
    fee = (assets * (compoundFactor - RAY)) / compoundFactor;
  }

  /**
   * @dev Calculate withdrawal fee for a given amount
   * @param amount The amount of assets being withdrawn
   * @param account The account to check for custom fee structure
   * @return fee The amount of withdrawal fee to be deducted
   */
  function _computeWithdrawalFee(
    uint256 amount,
    address account
  ) internal view returns (uint256 fee) {
    // Get account-specific withdrawal fee or use default
    uint256 feeRate = accountWithdrawalFee[account] != 0
      ? accountWithdrawalFee[account]
      : withdrawalFeeRate;

    // Calculate fee amount
    fee = amount.mulDiv(feeRate, RAY, Math.Rounding.Up);
  }

  /**
   * @dev Calculate and return the manager and protocol shares to be minted as fees
   * Total fees are the sum of the management and performance fees
   * Manager shares are the fees that go to the manager, it is the difference between the total fees and the
   * protocol fees
   * Protocol shares are the fees that go to the protocol
   * @return feeShares The total fees
   * @return pricePerShare The price per share (always 18 decimals)
   */
  function getFeeData()
    public
    view
    returns (uint256 feeShares, uint256 pricePerShare)
  {
    uint256 currentAssets = totalAssets();
    uint256 shares = totalSupply();

    uint256 timeElapsedFee = block.timestamp - lastFeeTime;

    uint256 annualManagementFees = currentAssets.mulDiv(
      managementFeeRate,
      RAY,
      Math.Rounding.Up
    );
    uint256 managementFeeAssets = annualManagementFees.mulDiv(
      timeElapsedFee,
      365 days,
      Math.Rounding.Up
    );

    /**
     * This represents the PPS before performance fee dilution
     * @dev Add 1 to shares to avoid division by zero
     */
    if (shares == 0) shares = 1;

    pricePerShare = ((currentAssets + 1) - managementFeeAssets)
      .mulDiv(1e18, shares, Math.Rounding.Up);

    uint256 performanceFeeAssets;
    if (highWaterMark < pricePerShare) {
      uint256 profitPerShare = pricePerShare - highWaterMark;

      uint256 profit = profitPerShare.mulDiv(
        shares,
        1e18,
        Math.Rounding.Up
      );

      performanceFeeAssets = profit.mulDiv(
        performanceFeeRate,
        RAY,
        Math.Rounding.Up
      );

      pricePerShare = (currentAssets -
        (managementFeeAssets + performanceFeeAssets)).mulDiv(
          1e18,
          shares + 1,
          Math.Rounding.Up
        );
    }

    uint256 totalFees = managementFeeAssets + performanceFeeAssets;

    // Compensate for the dilution as a consequence of minting shares as fees
    feeShares = totalFees.mulDiv(
      shares,
      (currentAssets - totalFees) + 1,
      Math.Rounding.Up
    );

    return (feeShares, pricePerShare);
  }

  /** ======== INTERNAL HELPERS ======== */

  /**
   * @dev Add assets directly to earning pool
   * Deposit fee compensates for any deployment delay
   * @param assets The amount of assets to add
   */
  function _addAssets(uint256 assets) internal {
    // Checkpoint accumulated interest before changing asset balance
    _registerFundRevenue();

    // Add assets directly to earning pool
    _totalAssets += assets;
  }

  /**
   * @dev Immediately withdraw assets from earning pool
   * Reflects immediate liquidity availability for withdrawals
   * @param assets The amount of assets to withdraw
   */
  function _withdrawAssets(uint256 assets) internal {
    // Checkpoint accumulated interest before changing asset balance
    _registerFundRevenue();

    // Cap withdrawal to available assets
    if (_totalAssets < assets) assets = _totalAssets;

    // Immediately remove assets from earning pool
    _totalAssets -= assets;
  }

  function _registerFundRevenue() internal {
    /// @dev Edge case before start of first compound period at vault initialization
    if (block.timestamp < lastCompoundTime) return;

    uint256 timeElapsed = block.timestamp - lastCompoundTime;
    if (timeElapsed == 0) return;

    // Update total assets with accumulated rewards
    _totalAssets = totalAssets();

    // Update compound time to only include full compounding periods
    // slither-disable-next-line divide-before-multiply
    uint256 fullDays = timeElapsed / 1 days;
    lastCompoundTime += fullDays * 1 days;

    emit RateCheckpointUpdated(_totalAssets, yieldAPR);
  }

  /**
   * @dev Calculate and take management and performance fees
   * Fees are taken as vault shares sent to the fee recipients
   * @param feeRecipient The management fee recipient
   */
  function _takeFees(address feeRecipient) internal {
    uint256 timeElapsed = block.timestamp - lastFeeTime;
    if (timeElapsed == 0) return;

    (uint256 feeShares, uint256 pricePerShare) = getFeeData();

    if (0 < feeShares) {
      _mint(feeRecipient, feeShares);
      lastFeeTime = block.timestamp;
    }

    if (highWaterMark < pricePerShare) highWaterMark = pricePerShare;

    /// @dev This call should always return early but we call it for safety
    _registerFundRevenue();
  }

  /** ======== ADMIN ======== */

  /**
   * @notice Set new total assets to handle capital losses or gains
   * @param newTotalAssets The new total assets amount
   * @dev This function should be called when there are capital losses/gains that need to be recorded
   */
  function setTotalAssets(uint256 newTotalAssets) external onlyOwner {
    uint256 oldTotalAssets = totalAssets();
    _totalAssets = newTotalAssets;

    // Reset compound time to next day boundary to maintain cross-chain sync
    lastCompoundTime = ((block.timestamp / 1 days) + 1) * 1 days;

    emit TotalAssetsUpdated(oldTotalAssets, newTotalAssets);
  }

  /**
   * @notice Updates the APR used for rate calculations
   * @param newAPR The new APR in RAY
   */
  function updateAPR(uint256 newAPR) external onlyOwner {
    // Snapshot accumulated interest with current APR
    _registerFundRevenue();

    uint256 oldAPR = yieldAPR;
    // Then update APR for future calculations
    yieldAPR = newAPR;

    emit APRUpdated(yieldAPR, oldAPR);
  }

  /**
   * @dev Update fee rates for the vault
   * @param managementRate_ The new management fee rate in RAY
   * @param performanceRate_ The new performance fee rate in RAY
   * @param withdrawalRate_ The new withdrawal fee rate in RAY
   */
  function updateFeeRates(
    uint256 managementRate_,
    uint256 performanceRate_,
    uint256 withdrawalRate_
  ) external onlyOwner {
    if (
      RAY < managementRate_ ||
      RAY < performanceRate_ ||
      RAY < withdrawalRate_
    ) revert RateAboveHundredPercent();

    managementFeeRate = managementRate_;
    performanceFeeRate = performanceRate_;
    withdrawalFeeRate = withdrawalRate_;

    emit FeeRatesUpdated(
      managementRate_,
      performanceRate_,
      withdrawalRate_
    );
  }

  /**
   * @dev Set a custom fee structure for a specific account
   * @param account The account to set the custom fee structure for
   * @param withdrawalFee The custom withdrawal fee in RAY
   */
  function setAccountWithdrawalFee(
    address account,
    uint256 withdrawalFee
  ) external onlyOwner {
    accountWithdrawalFee[account] = withdrawalFee;

    emit AccountWithdrawalFeeSet(account, withdrawalFee);
  }

  /**
   * @notice Update the deployment delay period
   * @param newDeploymentDelay The new deployment delay in days
   */
  function updateDeploymentDelay(
    uint8 newDeploymentDelay
  ) external onlyOwner {
    uint8 oldDelay = deploymentDelay;
    deploymentDelay = newDeploymentDelay;

    emit DeploymentDelayUpdated(oldDelay, newDeploymentDelay);
  }

  /**
   * @notice Update the high water mark for performance fee calculations
   * @param newHighWaterMark The new high water mark (in 18 decimals)
   */
  function updateHighWaterMark(
    uint256 newHighWaterMark
  ) external onlyOwner {
    uint256 oldHighWaterMark = highWaterMark;
    highWaterMark = newHighWaterMark;

    emit HighWaterMarkUpdated(oldHighWaterMark, newHighWaterMark);
  }

  /**
   * @notice Update the gas fee required for withdrawal requests
   * @param newWithdrawalGasFee The new gas fee amount in wei
   */
  function updateWithdrawalGasFee(
    uint256 newWithdrawalGasFee
  ) external onlyOwner {
    uint256 oldGasFee = withdrawalGasFee;
    withdrawalGasFee = newWithdrawalGasFee;

    emit WithdrawalGasFeeUpdated(oldGasFee, newWithdrawalGasFee);
  }
}
