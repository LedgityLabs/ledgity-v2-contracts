// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library LedgityDataProvider {
  /**
   * Structure representing a queued withdrawal request (internal storage)
   * @param user Address of the user who requested withdrawal
   * @param assets Amount of underlying assets to withdraw
   * @param timestamp When the withdrawal request was created
   * @param processed Whether the request has been fulfilled
   */
  struct WithdrawalRequest {
    address user;
    uint256 assets;
    uint256 timestamp;
    bool processed;
  }

  /**
   * Structure representing a queued withdrawal request (read view)
   * @param requestId Unique identifier for the withdrawal request
   * @param user Address of the user who requested withdrawal
   * @param assets Amount of underlying assets to withdraw
   * @param timestamp When the withdrawal request was created
   * @param processed Whether the request has been fulfilled
   * @param hasFeeReduction Whether the user has a fee reduction
   */
  struct WithdrawalRequestRead {
    uint256 requestId;
    address user;
    uint256 assets;
    uint256 timestamp;
    bool processed;
    bool hasFeeReduction;
  }

  /**
   * @notice Get withdrawal requests with optional filtering
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeBalanceForFeeReduction_ Minimum stake balance required for fee reduction
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests with read structure
   */
  function getWithdrawalRequests(
    WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeBalanceForFeeReduction_,
    bool onlyPending,
    uint256 maxRange
  ) external view returns (WithdrawalRequestRead[] memory filteredRequests) {
    return _getFilteredRequests(
      requests_,
      stakeToken_,
      stakeBalanceForFeeReduction_,
      address(0),
      onlyPending,
      maxRange
    );
  }

  /**
   * @notice Get withdrawal requests for a specific user
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeBalanceForFeeReduction_ Minimum stake balance required for fee reduction
   * @param user The user address
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests for the user with read structure
   */
  function getUserWithdrawalRequests(
    WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeBalanceForFeeReduction_,
    address user,
    bool onlyPending,
    uint256 maxRange
  ) external view returns (WithdrawalRequestRead[] memory filteredRequests) {
    return _getFilteredRequests(
      requests_,
      stakeToken_,
      stakeBalanceForFeeReduction_,
      user,
      onlyPending,
      maxRange
    );
  }

  /**
   * @notice Get specific withdrawal requests by their IDs
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeBalanceForFeeReduction_ Minimum stake balance required for fee reduction
   * @param requestIds Array of request IDs to fetch
   * @return selectedRequests Array of withdrawal requests corresponding to the IDs with read structure
   */
  function getWithdrawalRequestsByIds(
    WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeBalanceForFeeReduction_,
    uint256[] calldata requestIds
  ) external view returns (WithdrawalRequestRead[] memory selectedRequests) {
    selectedRequests = new WithdrawalRequestRead[](requestIds.length);
    bool stakeTokenSet = address(stakeToken_) != address(0);

    for (uint256 i; i < requestIds.length; i++) {
      WithdrawalRequest storage request = requests_[requestIds[i]];

      bool hasFeeReduction;
      if (stakeTokenSet) {
        hasFeeReduction =
          stakeToken_.balanceOf(request.user) >= stakeBalanceForFeeReduction_;
      }

      selectedRequests[i] = WithdrawalRequestRead({
        requestId: requestIds[i],
        user: request.user,
        assets: request.assets,
        timestamp: request.timestamp,
        processed: request.processed,
        hasFeeReduction: hasFeeReduction
      });
    }
  }

  /**
   * @notice Internal helper to filter withdrawal requests with various options
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeBalanceForFeeReduction_ Minimum stake balance required for fee reduction
   * @param user Filter by user address (address(0) = no filter)
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = no limit)
   * @return filteredRequests Array of matching withdrawal requests with read structure
   */
  function _getFilteredRequests(
    WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeBalanceForFeeReduction_,
    address user,
    bool onlyPending,
    uint256 maxRange
  ) private view returns (WithdrawalRequestRead[] memory filteredRequests) {
    uint256 totalRequests = requests_.length;

    // Determine search range - start from latest requests
    uint256 searchLimit = maxRange > 0 && maxRange < totalRequests
      ? maxRange
      : totalRequests;

    // Count matching requests (search backwards from latest)
    uint256 matchCount;
    uint256 searchCount;
    for (
      uint256 i = totalRequests - 1;
      searchCount < searchLimit;
      i--
    ) {
      searchCount++;

      WithdrawalRequest storage request = requests_[i];
      if (
        (user == address(0) || request.user == user) &&
        (!onlyPending || !request.processed)
      ) {
        matchCount++;
      }

      if (i == 0) break;
    }

    // Create result array
    filteredRequests = new WithdrawalRequestRead[](matchCount);
    bool stakeTokenSet = address(stakeToken_) != address(0);
    uint256 resultIndex;

    // Fill results (search backwards from latest, but fill array in reverse for oldest-first output)
    searchCount = 0;
    for (
      uint256 i = totalRequests - 1;
      searchCount < searchLimit && resultIndex < matchCount;
      i--
    ) {
      searchCount++;

      WithdrawalRequest storage request = requests_[i];
      if (
        (user == address(0) || request.user == user) &&
        (!onlyPending || !request.processed)
      ) {
        bool hasFeeReduction;
        if (stakeTokenSet) {
          hasFeeReduction =
            stakeToken_.balanceOf(request.user) >= stakeBalanceForFeeReduction_;
        }

        // Fill array from end to maintain oldest-first order in output
        filteredRequests[
          matchCount - 1 - resultIndex
        ] = WithdrawalRequestRead({
          requestId: i,
          user: request.user,
          assets: request.assets,
          timestamp: request.timestamp,
          processed: request.processed,
          hasFeeReduction: hasFeeReduction
        });
        resultIndex++;
      }

      if (i == 0) break;
    }
  }
}
