// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";

/**
 * @title LedgityDataProvider
 * @notice Read-only views over the withdrawal requests of a Ledgity vault (LedgityYieldVault,
 *         LedgityYieldVaultSonic, FixedTermInvestmentVault)
 * @dev Stateless: every value is read from the vault passed in, through its public getters.
 *      These views used to live in the vaults, they were moved here to keep the vaults under
 *      the 24,576-byte contract size limit.
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract LedgityDataProvider is ILedgityDataProvider {
  /// @inheritdoc ILedgityDataProvider
  function getWithdrawalRequests(
    address vault,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (WithdrawalRequestRead[] memory filteredRequests)
  {
    return
      _getFilteredRequests(
        ILedgityYieldVault(vault),
        address(0),
        onlyPending,
        maxRange
      );
  }

  /// @inheritdoc ILedgityDataProvider
  function getUserWithdrawalRequests(
    address vault,
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (WithdrawalRequestRead[] memory filteredRequests)
  {
    return
      _getFilteredRequests(
        ILedgityYieldVault(vault),
        user,
        onlyPending,
        maxRange
      );
  }

  /// @inheritdoc ILedgityDataProvider
  function getWithdrawalRequestsByIds(
    address vault,
    uint256[] calldata requestIds
  )
    external
    view
    returns (WithdrawalRequestRead[] memory selectedRequests)
  {
    ILedgityYieldVault vault_ = ILedgityYieldVault(vault);
    IERC20 stakeToken = vault_.stakeToken();
    uint256 stakeForFeeReduction = vault_.stakeForFeeReduction();

    selectedRequests = new WithdrawalRequestRead[](requestIds.length);
    for (uint256 i; i < requestIds.length; i++) {
      selectedRequests[i] = _readRequest(
        vault_,
        requestIds[i],
        stakeToken,
        stakeForFeeReduction
      );
    }
  }

  /**
   * @notice Internal helper to filter withdrawal requests with various options
   * @param vault The vault holding the requests
   * @param user Filter by user address (address(0) = no filter)
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to search, latest first (0 = no limit)
   * @return filteredRequests Array of matching withdrawal requests, oldest first
   */
  function _getFilteredRequests(
    ILedgityYieldVault vault,
    address user,
    bool onlyPending,
    uint256 maxRange
  ) private view returns (WithdrawalRequestRead[] memory filteredRequests) {
    uint256 totalRequests = vault.getWithdrawalRequestCount();

    // If there are no requests, return an empty array to avoid underflow on (totalRequests - 1)
    if (totalRequests == 0) {
      return new WithdrawalRequestRead[](0);
    }

    // Determine search range - start from latest requests
    uint256 searchLimit = maxRange > 0 && maxRange < totalRequests
      ? maxRange
      : totalRequests;
    uint256 firstSearched = totalRequests - searchLimit;

    // Count matching requests
    uint256 matchCount;
    for (uint256 i = firstSearched; i < totalRequests; i++) {
      (address requester, , , bool processed) = vault.withdrawalRequests(
        i
      );
      if (_matches(requester, processed, user, onlyPending)) matchCount++;
    }

    // Fill results oldest first
    filteredRequests = new WithdrawalRequestRead[](matchCount);
    IERC20 stakeToken = vault.stakeToken();
    uint256 stakeForFeeReduction = vault.stakeForFeeReduction();
    uint256 resultIndex;
    for (
      uint256 i = firstSearched;
      i < totalRequests && resultIndex < matchCount;
      i++
    ) {
      WithdrawalRequestRead memory request = _readRequest(
        vault,
        i,
        stakeToken,
        stakeForFeeReduction
      );
      if (_matches(request.user, request.processed, user, onlyPending)) {
        filteredRequests[resultIndex++] = request;
      }
    }
  }

  /// @dev Whether a request passes the user and pending filters
  function _matches(
    address requester,
    bool processed,
    address user,
    bool onlyPending
  ) private pure returns (bool) {
    return
      (user == address(0) || requester == user) &&
      (!onlyPending || !processed);
  }

  /// @dev Reads one request from the vault into the read structure
  function _readRequest(
    ILedgityYieldVault vault,
    uint256 requestId,
    IERC20 stakeToken,
    uint256 stakeForFeeReduction
  ) private view returns (WithdrawalRequestRead memory request) {
    request.requestId = requestId;
    (
      request.user,
      request.amount,
      request.timestamp,
      request.processed
    ) = vault.withdrawalRequests(requestId);
    if (address(stakeToken) != address(0)) {
      request.hasFeeReduction =
        stakeToken.balanceOf(request.user) >= stakeForFeeReduction;
    }
  }
}
