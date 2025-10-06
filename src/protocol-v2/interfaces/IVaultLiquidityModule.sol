// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IVaultLiquidityModule {
  struct VaultLiquidityInitParams {
    uint256 highWaterMark;
    uint256 initialAssetsPerShare; // Initial assets per share of vault (asset decimals)
    uint256 yieldAPR;
    uint256 managementFeeRate;
    uint256 performanceFeeRate;
    uint256 withdrawalFeeRate;
    uint256 withdrawalGasFee;
    uint8 deploymentDelay;
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

  event DeploymentDelayUpdated(uint8 oldDelay, uint8 newDelay);

  /** ======== FUNCTIONS ======== */

  function RAY() external view returns (uint256);

  function lastCompoundTime() external view returns (uint256);

  function lastFeeTime() external view returns (uint256);

  function highWaterMark() external view returns (uint256);

  function deploymentDelay() external view returns (uint8);

  function yieldAPR() external view returns (uint256);

  function managementFeeRate() external view returns (uint256);

  function performanceFeeRate() external view returns (uint256);

  function withdrawalFeeRate() external view returns (uint256);

  function withdrawalGasFee() external view returns (uint256);

  function accountWithdrawalFee(
    address account
  ) external view returns (uint256);

  function totalAssets()
    external
    view
    returns (uint256 currentTotalAssets);

  function convertToShares(
    uint256 assets
  ) external view returns (uint256 shares);

  function convertToAssets(
    uint256 shares
  ) external view returns (uint256 assets);

  function setTotalAssets(uint256 newTotalAssets) external;

  function updateAPR(uint256 newAPR) external;

  function updateFeeRates(
    uint256 managementRate_,
    uint256 performanceRate_,
    uint256 withdrawalRate_
  ) external;

  function setAccountWithdrawalFee(
    address account,
    uint256 withdrawalFee
  ) external;

  function updateDeploymentDelay(uint8 newDeploymentDelay) external;
}
