// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";

interface ILedgityYieldVault is ILedgityDataProvider {
  struct VaultParams {
    string name;
    string symbol;
    IERC20 asset;
    IERC20 lToken;
    IERC20 stakeToken;
    uint256 stakeForFeeReduction;
    uint256 stakeForInstantWithdrawal;
    address globalOwner;
    address globalPause;
    address globalAccessList;
    address liquidityManager;
    address payable feeRecipient;
    uint256 liquidityBufferRate;
    IAaveLendingPoolV3 aaveLendingPool;
  }

  function initialize(
    VaultParams calldata params,
    IVaultLiquidityModule.VaultLiquidityInitParams
      calldata vaultLiquidityInitParams
  ) external;

  function lToken() external view returns (IERC20);

  function liquidityManager() external view returns (address);

  function feeRecipient() external view returns (address payable);

  function liquidityBufferRate() external view returns (uint256);

  function hasBufferStrategy() external view returns (bool);

  function aaveLendingPool()
    external
    view
    returns (IAaveLendingPoolV3);

  function aToken() external view returns (IERC20);

  function stakeToken() external view returns (IERC20);

  function stakeForFeeReduction() external view returns (uint256);

  function withdrawalRequests(
    uint256
  )
    external
    view
    returns (
      address user,
      uint256 assets,
      uint256 timestamp,
      bool processed
    );

  function getBufferAssets() external view returns (uint256);

  function getWithdrawalRequests(
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    );

  function getUserWithdrawalRequests(
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    );

  function getWithdrawalRequestsByIds(
    uint256[] calldata requestIds
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    );

  function getWithdrawalRequestCount()
    external
    view
    returns (uint256);

  function migrateLToken(
    uint256 amount
  ) external returns (uint256 shares);

  function deposit(
    uint256 assets,
    address receiver
  ) external returns (uint256);

  function mint(
    uint256 shares,
    address receiver
  ) external returns (uint256);

  function withdraw(
    uint256 assets_,
    address receiver_,
    address owner_
  ) external returns (uint256);

  function redeem(
    uint256 shares_,
    address receiver_,
    address owner_
  ) external returns (uint256);

  function requestWithdrawal(uint256 shares) external payable;

  function harvestFees() external;

  function depositToBuffer(uint256 amount) external;

  function skimBuffer(uint256 amount) external;

  function processRequests(
    uint256[] calldata requestIds,
    uint256 addedLiquidity
  ) external;

  function updateVaultManagers(
    address newLiquidityManager,
    address payable newFeeRecipient
  ) external;

  function updateBufferRate(uint256 bufferRate) external;

  function updateVaultParams(
    IERC20 newLToken,
    IERC20 newStakeToken,
    uint256 newStakeForFeeReduction,
    uint256 newStakeForInstantWithdrawal,
    IAaveLendingPoolV3 newAaveLendingPool
  ) external;
}
