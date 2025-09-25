// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

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

  /** ======== STORAGE ======== */

  // Base rate constant representing 100%
  uint256 public constant RATE_BASE = 100_000;
  uint256 public constant RAY = 1e27;
  uint256 public constant APR_RATE_OFFSET = RAY / RATE_BASE;

  // Total assets under management
  uint256 private _totalAssets;
  // Offset between vault decimals and underlying asset decimals
  uint8 public decimalsOffset;

  // Last timestamp when assets were compounded (only full compounding periods)
  uint256 public lastCompoundTime;
  // The timestamp of the last fee calculation, used to compute management fees
  uint256 public lastFeeTime;
  // The highest price per share ever reached, performance fees are taken when
  // the price per share is above this value
  uint256 public highWaterMark;

  // Deployment delay period in days for calculating deposit fees
  uint256 public deploymentDelay;

  // Annual Percentage Rate in RATE_BASE
  uint256 public yieldAPR;

  // Management fee in RATE_BASE
  uint256 public managementFeeRate;
  // Performance fee in RATE_BASE
  uint256 public performanceFeeRate;
  // Withdrawal fee in RATE_BASE
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
    decimalsOffset = 18 - decimals();

    // Initialize high water mark at 1 share = 1 asset if not specified
    highWaterMark = params.highWaterMark != 0
      ? params.highWaterMark
      : 10 ** decimals();
    deploymentDelay = params.deploymentDelay;
    yieldAPR = params.yieldAPR;

    managementFeeRate = params.managementFeeRate;
    performanceFeeRate = params.performanceFeeRate;
    withdrawalFeeRate = params.withdrawalFeeRate;
    withdrawalGasFee = params.withdrawalGasFee;

    lastCompoundTime = block.timestamp;
    lastFeeTime = block.timestamp;

    emit APRUpdated(params.yieldAPR, 0);
  }

  /** ======== EVENTS ======== */

  event RateCheckpointUpdated(uint256 newRate, uint256 newAPR);

  event APRUpdated(uint256 newAPR, uint256 oldAPR);

  event FeeRatesUpdated(
    uint256 managementFeeRate,
    uint256 performanceRate,
    uint256 withdrawalRate
  );

  event AccountWithdrawalFeeSet(
    address indexed account,
    uint256 withdrawalFee
  );

  event TotalAssetsUpdated(
    uint256 oldTotalAssets,
    uint256 newTotalAssets
  );

  event DeploymentDelayUpdated(uint256 oldDelay, uint256 newDelay);

  /** ======== OVERRIDES ======== */

  /**
   * @dev Get the offset between vault decimals and underlying asset decimals
   * @return decimalsOffset The offset between vault decimals and underlying asset decimals
   * @dev In the form of a function to allow parent contracts to call this override
   */
  function _decimalsOffset()
    internal
    view
    override(ERC4626Upgradeable)
    returns (uint8)
  {
    return decimalsOffset;
  }

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

    // Time elapsed since last compound
    uint256 timeElapsed = block.timestamp - lastCompoundTime;
    // Calculate number of full days elapsed
    uint256 fullDays = timeElapsed / 1 days;

    if (0 < fullDays) {
      // We want an APR with RAY precision that we can use as a coefficient (100% = 1)
      uint256 aprBaseOneRay = yieldAPR * APR_RATE_OFFSET;
      // Daily rate = APR / 365
      uint256 dailyRatio = aprBaseOneRay / 365;

      // Apply daily compounding for full days only
      for (uint256 i; i < fullDays; i++) {
        currentTotalAssets =
          (currentTotalAssets * (RAY + dailyRatio)) /
          RAY;
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

    if (supply == 0 || currentAssets == 0) {
      return assets;
    }

    shares = assets.mulDiv(supply, currentAssets);
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

    if (supply == 0 || currentAssets == 0) {
      return shares;
    }

    assets = shares.mulDiv(currentAssets, supply);
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
    // Convert APR to daily rate with RAY precision
    uint256 aprBaseOneRay = yieldAPR * APR_RATE_OFFSET;
    uint256 dailyRate = aprBaseOneRay / 365;

    // Calculate: (1 + dailyRate)^deploymentDelay
    uint256 compoundFactor = RAY;
    for (uint256 i; i < deploymentDelay; i++) {
      compoundFactor = (compoundFactor * (RAY + dailyRate)) / RAY;
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
    fee = amount.mulDiv(feeRate, RATE_BASE, Math.Rounding.Up);
  }

  /**
   * @dev Calculate and return the manager and protocol shares to be minted as fees
   * Total fees are the sum of the management and performance fees
   * Manager shares are the fees that go to the manager, it is the difference between the total fees and the
   * protocol fees
   * Protocol shares are the fees that go to the protocol
   * @return totalFeeShares The total fees
   * @return pricePerShare The price per share
   */
  function _computeFeeData()
    internal
    view
    returns (uint256 totalFeeShares, uint256 pricePerShare)
  {
    uint256 currentAssets = totalAssets();
    uint256 shares = totalSupply();

    uint256 timeElapsedFee = block.timestamp - lastFeeTime;

    uint256 annualManagementFees = currentAssets.mulDiv(
      managementFeeRate,
      RATE_BASE,
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
    uint256 sharesDenominator = shares + 10 ** _decimalsOffset();
    // Additional protection when decimalsOffset is 0 and shares is 0
    if (sharesDenominator == 0) sharesDenominator = 1;

    pricePerShare = (10 ** decimals()).mulDiv(
      (currentAssets + 1) - managementFeeAssets,
      sharesDenominator,
      Math.Rounding.Up
    );

    uint256 performanceFeeAssets;
    if (highWaterMark < pricePerShare) {
      uint256 profitPerShare = pricePerShare - highWaterMark;

      uint256 profit = profitPerShare.mulDiv(
        shares,
        10 ** decimals(),
        Math.Rounding.Up
      );

      performanceFeeAssets = profit.mulDiv(
        performanceFeeRate,
        RATE_BASE,
        Math.Rounding.Up
      );

      pricePerShare = (10 ** decimals()).mulDiv(
        currentAssets - (managementFeeAssets + performanceFeeAssets),
        shares + 1,
        Math.Rounding.Up
      );
    }

    uint256 totalFees = managementFeeAssets + performanceFeeAssets;

    // Compensate for the dilution as a consequence of minting shares as fees
    totalFeeShares = totalFees.mulDiv(
      shares + 10 ** _decimalsOffset(),
      (currentAssets - totalFees) + 1,
      Math.Rounding.Up
    );

    return (totalFeeShares, pricePerShare);
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

    (
      uint256 totalFeeShares,
      uint256 pricePerShare
    ) = _computeFeeData();

    if (0 < totalFeeShares) {
      _mint(feeRecipient, totalFeeShares);
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

    // Reset compound time to current timestamp to avoid double counting
    lastCompoundTime = block.timestamp;

    emit TotalAssetsUpdated(oldTotalAssets, newTotalAssets);
  }

  /**
   * @notice Updates the APR used for rate calculations
   * @param newAPR The new APR in RATE_BASE
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
   * @param managementRate_ The new management fee rate in RATE_BASE
   * @param performanceRate_ The new performance fee rate in RATE_BASE
   * @param withdrawalRate_ The new withdrawal fee rate in RATE_BASE
   */
  function updateFeeRates(
    uint256 managementRate_,
    uint256 performanceRate_,
    uint256 withdrawalRate_
  ) external onlyOwner {
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
   * @param withdrawalFee The custom withdrawal fee in RATE_BASE
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
    uint256 newDeploymentDelay
  ) external onlyOwner {
    uint256 oldDelay = deploymentDelay;
    deploymentDelay = newDeploymentDelay;

    emit DeploymentDelayUpdated(oldDelay, newDeploymentDelay);
  }
}
