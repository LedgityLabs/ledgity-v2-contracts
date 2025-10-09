// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILedgityDataProvider } from "../interfaces/ILedgityDataProvider.sol";

library LedgityDataProvider {
  /**
   * @notice Get withdrawal requests with optional filtering
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeForFeeReduction_ Minimum stake balance required for fee reduction
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests with read structure
   */
  function getWithdrawalRequests(
    ILedgityDataProvider.WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeForFeeReduction_,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory filteredRequests
    )
  {
    return
      _getFilteredRequests(
        requests_,
        stakeToken_,
        stakeForFeeReduction_,
        address(0),
        onlyPending,
        maxRange
      );
  }

  /**
   * @notice Get withdrawal requests for a specific user
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeForFeeReduction_ Minimum stake balance required for fee reduction
   * @param user The user address
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests for the user with read structure
   */
  function getUserWithdrawalRequests(
    ILedgityDataProvider.WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeForFeeReduction_,
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory filteredRequests
    )
  {
    return
      _getFilteredRequests(
        requests_,
        stakeToken_,
        stakeForFeeReduction_,
        user,
        onlyPending,
        maxRange
      );
  }

  /**
   * @notice Get specific withdrawal requests by their IDs
   * @param requests_ Storage array of withdrawal requests
   * @param stakeToken_ Stake token contract for fee reduction checks
   * @param stakeForFeeReduction_ Minimum stake balance required for fee reduction
   * @param requestIds Array of request IDs to fetch
   * @return selectedRequests Array of withdrawal requests corresponding to the IDs with read structure
   */
  function getWithdrawalRequestsByIds(
    ILedgityDataProvider.WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeForFeeReduction_,
    uint256[] calldata requestIds
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory selectedRequests
    )
  {
    selectedRequests = new ILedgityDataProvider.WithdrawalRequestRead[](
      requestIds.length
    );
    bool stakeTokenSet = address(stakeToken_) != address(0);

    for (uint256 i; i < requestIds.length; i++) {
      ILedgityDataProvider.WithdrawalRequest
        storage request = requests_[requestIds[i]];

      bool hasFeeReduction;
      if (stakeTokenSet) {
        hasFeeReduction =
          stakeToken_.balanceOf(request.user) >=
          stakeForFeeReduction_;
      }

      selectedRequests[i] = ILedgityDataProvider
        .WithdrawalRequestRead({
          requestId: requestIds[i],
          user: request.user,
          amount: request.amount,
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
   * @param stakeForFeeReduction_ Minimum stake balance required for fee reduction
   * @param user Filter by user address (address(0) = no filter)
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = no limit)
   * @return filteredRequests Array of matching withdrawal requests with read structure
   */
  function _getFilteredRequests(
    ILedgityDataProvider.WithdrawalRequest[] storage requests_,
    IERC20 stakeToken_,
    uint256 stakeForFeeReduction_,
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    private
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory filteredRequests
    )
  {
    uint256 totalRequests = requests_.length;

    // If there are no requests, return an empty array to avoid underflow on (totalRequests - 1)
    if (totalRequests == 0) {
      return new ILedgityDataProvider.WithdrawalRequestRead[](0);
    }

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

      ILedgityDataProvider.WithdrawalRequest
        storage request = requests_[i];
      if (
        (user == address(0) || request.user == user) &&
        (!onlyPending || !request.processed)
      ) {
        matchCount++;
      }

      if (i == 0) break;
    }

    // Create result array
    filteredRequests = new ILedgityDataProvider.WithdrawalRequestRead[](
      matchCount
    );
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

      ILedgityDataProvider.WithdrawalRequest
        storage request = requests_[i];
      if (
        (user == address(0) || request.user == user) &&
        (!onlyPending || !request.processed)
      ) {
        bool hasFeeReduction;
        if (stakeTokenSet) {
          hasFeeReduction =
            stakeToken_.balanceOf(request.user) >=
            stakeForFeeReduction_;
        }

        // Fill array from end to maintain oldest-first order in output
        filteredRequests[
          matchCount - 1 - resultIndex
        ] = ILedgityDataProvider.WithdrawalRequestRead({
          requestId: i,
          user: request.user,
          amount: request.amount,
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
