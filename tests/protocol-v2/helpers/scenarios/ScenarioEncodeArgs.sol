// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title Args
 * @notice Helper functions for encoding action arguments in scenario tests
 * @dev Provides type-safe encoding functions for all action types
 */
library Args {
  function depositAssets(
    uint256 /* assets */,
    address receiver
  ) internal pure returns (bytes memory) {
    return abi.encode(receiver);
  }

  function mintShares(
    uint256 /* shares */,
    address receiver
  ) internal pure returns (bytes memory) {
    return abi.encode(receiver);
  }

  function withdrawAssets(
    uint256 /* assets */,
    address receiver,
    address owner
  ) internal pure returns (bytes memory) {
    return abi.encode(receiver, owner);
  }

  function redeemShares(
    uint256 /* shares */,
    address receiver,
    address owner
  ) internal pure returns (bytes memory) {
    return abi.encode(receiver, owner);
  }

  function requestWithdrawalShares(
    uint256 /* shares */,
    uint256 gasFee
  ) internal pure returns (bytes memory) {
    return abi.encode(gasFee);
  }

  function processRequestsAssets(
    uint256[] memory requestIds,
    uint256 addAssets
  ) internal pure returns (bytes memory) {
    return abi.encode(requestIds, addAssets);
  }

  function updateFees(
    uint256 managementFee,
    uint256 performanceFee,
    uint256 withdrawalFee
  ) internal pure returns (bytes memory) {
    return abi.encode(managementFee, performanceFee, withdrawalFee);
  }

  function none() internal pure returns (bytes memory) {
    return "";
  }
}
