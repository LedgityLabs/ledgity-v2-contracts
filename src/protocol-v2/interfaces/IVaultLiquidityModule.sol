// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IVaultLiquidityModule {
  struct VaultLiquidityInitParams {
    uint256 highWaterMark;
    uint256 deploymentDelay;
    uint256 yieldAPR;
    uint256 managementFeeRate;
    uint256 performanceFeeRate;
    uint256 withdrawalFeeRate;
    uint256 withdrawalGasFee;
  }

  function RATE_BASE() external view returns (uint256);

  function RAY() external view returns (uint256);

  function APR_RATE_OFFSET() external view returns (uint256);

  function lastCompoundTime() external view returns (uint256);

  function lastFeeTime() external view returns (uint256);

  function highWaterMark() external view returns (uint256);

  function deploymentDelay() external view returns (uint256);

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

  function updateDeploymentDelay(uint256 newDeploymentDelay) external;
}
