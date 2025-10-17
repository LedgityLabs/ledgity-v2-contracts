// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";

interface IStakingRewardsDistributor {
  /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

  struct BaseRewardPeriod {
    uint256 startWeek;
    uint256 endWeek;
    uint256 totalAmount;
    uint256 weeklyAmount;
  }

  /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

  event BaseRewardsDeposited(
    uint256 indexed periodId,
    uint256 amount,
    uint256 startWeek,
    uint256 duration,
    uint256 weeklyAmount
  );

  event ProtocolFeesDeposited(
    uint256 amount,
    uint256 timestamp,
    uint256 totalSupply
  );

  event BaseRewardsClaimed(
    uint256 indexed tokenId,
    uint256 amount,
    uint256 fromWeek,
    uint256 toWeek
  );

  event ProtocolRewardsClaimed(
    uint256 indexed tokenId,
    uint256 amount
  );

  /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

  error NotOwner();
  error ZeroAmount();
  error ZeroDuration();
  error InvalidTokenId();
  error NotApprovedOrOwner();
  error OnlyStakingPositions();

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice StakingPositions contract address
  function staking() external view returns (IStakingPositions);

  /// @notice Reward token address (LDY)
  function token() external view returns (address);

  /// @notice Start time of the reward system
  function startTime() external view returns (uint256);

  /// @notice Last time base rewards were checkpointed
  function lastTokenTime() external view returns (uint256);

  /// @notice Current active base reward period ID
  function currentPeriodId() external view returns (uint256);

  /// @notice Base rewards per week for a specific period
  function baseRewardsPerWeek(
    uint256 periodId,
    uint256 week
  ) external view returns (uint256);

  /// @notice Last claim cursor for base rewards for each tokenId
  function baseRewardCursor(
    uint256 tokenId
  ) external view returns (uint256);

  /// @notice Last processed period cursor for base rewards for each tokenId
  function baseRewardPeriodCursor(
    uint256 tokenId
  ) external view returns (uint256);

  /// @notice Cumulative protocol rewards per token (scaled by 1e18)
  function cumulativeProtocolRewardsPerToken()
    external
    view
    returns (uint256);

  /// @notice Last recorded cumulative rewards per token for each NFT
  function protocolRewardsPerTokenPaid(
    uint256 tokenId
  ) external view returns (uint256);

  /// @notice Calculate total claimable rewards for a tokenId
  function claimable(
    uint256 tokenId
  )
    external
    view
    returns (uint256 baseRewards, uint256 protocolRewards);

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Deposit base rewards to be distributed over time
  /// @param amount Amount of tokens to distribute
  /// @param duration Duration in weeks for distribution
  function depositBaseRewards(
    uint256 amount,
    uint256 duration
  ) external;

  /// @notice Deposit protocol fee rewards for immediate distribution
  /// @param amount Amount of protocol fee tokens to distribute
  function depositProtocolFees(uint256 amount) external;

  /// @notice Update the addresses of the staking and token contracts
  /// @param staking_ Address of the staking contract
  /// @param token_ Address of the token contract
  function updateAddresses(address staking_, address token_) external;

  /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Claim all available rewards for a tokenId
  /// @param tokenId The NFT tokenId to claim rewards for
  /// @return baseRewards Amount of base rewards claimed
  /// @return protocolRewards Amount of protocol rewards claimed
  function claim(
    uint256 tokenId
  ) external returns (uint256 baseRewards, uint256 protocolRewards);

  /// @notice Claim all available rewards for a tokenId on withdrawal
  /// @param tokenId The NFT tokenId to claim rewards for
  /// @param to Address to receive the rewards
  function claimOnWithdrawal(uint256 tokenId, address to) external;

  /// @notice Claim rewards for multiple tokenIds
  /// @param tokenIds Array of tokenIds to claim for
  /// @return success True if all claims succeeded
  function claimMany(
    uint256[] calldata tokenIds
  ) external returns (bool success);
}
