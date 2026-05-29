// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";

interface IFixedTermInvestmentVault is ILedgityYieldVault {
  function maxDepositCapacity() external view returns (uint256);

  function operationEndDate() external view returns (uint256);

  function withdrawalRequestShares(
    uint256 requestId
  ) external view returns (uint256);

  function updateMaxDepositCapacity(
    uint256 maxDepositCapacity
  ) external;

  function updateOperationEndDate(uint256 operationEndDate) external;

  function withdrawalRequestsEnabled() external view returns (bool);

  function updateWithdrawalRequestsEnabled(bool enabled) external;

  function cancelPendingWithdrawalRequests(
    uint256[] calldata requestIds
  ) external;
}
