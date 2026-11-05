// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ILedgityDataProvider {
  /**
   * Structure representing a queued withdrawal request (internal storage)
   * @param user Address of the user who requested withdrawal
   * @param amount Amount of underlying assets to withdraw
   * @param timestamp When the withdrawal request was created
   * @param processed Whether the request has been fulfilled
   */
  struct WithdrawalRequest {
    address user;
    uint256 amount;
    uint256 timestamp;
    bool processed;
  }

  /**
   * @notice Structure representing a queued withdrawal request (read view)
   * @param requestId Unique identifier for the withdrawal request
   * @param user Address of the user who requested withdrawal
   * @param amount Amount of underlying assets to withdraw
   * @param timestamp When the withdrawal request was created
   * @param processed Whether the request has been fulfilled
   * @param hasFeeReduction Whether the user has a fee reduction
   */
  struct WithdrawalRequestRead {
    uint256 requestId;
    address user;
    uint256 amount;
    uint256 timestamp;
    bool processed;
    bool hasFeeReduction;
  }

  /**
   * @notice Get withdrawal requests with optional filtering
   * @param vault The vault holding the requests
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests with read structure
   */
  function getWithdrawalRequests(
    address vault,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (WithdrawalRequestRead[] memory filteredRequests);

  /**
   * @notice Get withdrawal requests for a specific user
   * @param vault The vault holding the requests
   * @param user The user address
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return filteredRequests Array of withdrawal requests for the user with read structure
   */
  function getUserWithdrawalRequests(
    address vault,
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (WithdrawalRequestRead[] memory filteredRequests);

  /**
   * @notice Get specific withdrawal requests by their IDs
   * @param vault The vault holding the requests
   * @param requestIds Array of request IDs to fetch
   * @return selectedRequests Array of withdrawal requests corresponding to the IDs with read structure
   */
  function getWithdrawalRequestsByIds(
    address vault,
    uint256[] calldata requestIds
  )
    external
    view
    returns (WithdrawalRequestRead[] memory selectedRequests);
}
