// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title Args
 * @notice Helper functions for encoding action arguments in scenario tests
 * @dev Provides type-safe encoding functions for all action types
 */
library Args {
  function depositAssets(
    uint256 assets,
    address receiver
  ) internal pure returns (bytes memory) {
    return abi.encode(assets, receiver);
  }

  function mintShares(
    uint256 shares,
    address receiver
  ) internal pure returns (bytes memory) {
    return abi.encode(shares, receiver);
  }

  function withdrawAssets(
    uint256 assets,
    address receiver,
    address owner
  ) internal pure returns (bytes memory) {
    return abi.encode(assets, receiver, owner);
  }

  function redeemShares(
    uint256 shares,
    address receiver,
    address owner
  ) internal pure returns (bytes memory) {
    return abi.encode(shares, receiver, owner);
  }

  function requestWithdrawalShares(
    uint256 shares,
    uint256 gasFee
  ) internal pure returns (bytes memory) {
    return abi.encode(shares, gasFee);
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

  function timeWarp(uint256 timeJump) internal pure returns (bytes memory) {
    return abi.encode(timeJump);
  }

  function harvestFees() internal pure returns (bytes memory) {
    return "";
  }

  function depositToBuffer(
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encode(amount);
  }

  function skimBuffer(uint256 amount) internal pure returns (bytes memory) {
    return abi.encode(amount);
  }

  function migrateLToken(
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encode(amount);
  }

  function updateAPR(uint256 newAPR) internal pure returns (bytes memory) {
    return abi.encode(newAPR);
  }

  function setTotalAssets(
    uint256 amount
  ) internal pure returns (bytes memory) {
    return abi.encode(amount);
  }
}
