// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
// Extensions
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStakingRewardsDistributor } from "src/protocol-v2/interfaces/IStakingRewardsDistributor.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";

/**
 * @title Staking Rewards Distributor
 * @notice Dual reward system for staking
 * @dev Implements two types of rewards:
 *      1. Base rewards: Time-distributed over specified periods
 *      2. Protocol fee rewards: Instantly distributed to current stakers
 *
 * @author Modified from Velodrome (https://github.com/velodrome-finance/contracts/blob/main/contracts/VotingEscrow.sol)
 * @author Ledgity, vBlackwhale (https://github.com/vblackwhale)
 *
 */
contract StakingRewardsDistributor is
  IStakingRewardsDistributor,
  AdministeredUpgradable,
  ReentrancyGuard
{
  using SafeERC20 for IERC20;

  /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

  uint256 public constant WEEK = 7 * 86400;
  uint256 private constant PRECISION = 1e18;

  /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingRewardsDistributor
  IStakingPositions public staking;
  /// @inheritdoc IStakingRewardsDistributor
  address public token;

  /// @inheritdoc IStakingRewardsDistributor
  uint256 public startTime;
  /// @inheritdoc IStakingRewardsDistributor
  uint256 public lastTokenTime;

  // Base rewards state
  /// @inheritdoc IStakingRewardsDistributor
  uint256 public currentPeriodId;
  mapping(uint256 _periodId => BaseRewardPeriod)
    public baseRewardPeriods;
  /// @inheritdoc IStakingRewardsDistributor
  mapping(uint256 _periodId => mapping(uint256 _week => uint256 _amount))
    public baseRewardsPerWeek;
  /// @inheritdoc IStakingRewardsDistributor
  mapping(uint256 _tokenId => uint256 _weekCursor)
    public baseRewardCursor;
  /// @inheritdoc IStakingRewardsDistributor
  mapping(uint256 _tokenId => uint256 _periodCursor)
    public baseRewardPeriodCursor;

  // Protocol fee rewards state
  /// @inheritdoc IStakingRewardsDistributor
  uint256 public cumulativeProtocolRewardsPerToken;
  /// @inheritdoc IStakingRewardsDistributor
  mapping(uint256 _tokenId => uint256 _amount)
    public protocolRewardsPerTokenPaid;

  /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address staking_,
    address globalOwner_,
    address globalPause_,
    address globalAccessList_
  ) public initializer {
    staking = IStakingPositions(staking_);
    token = staking.token();

    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    startTime = currentWeek;
    lastTokenTime = currentWeek;

    __AdministeredUpgradable_init(
      globalOwner_,
      globalPause_,
      globalAccessList_
    );
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingRewardsDistributor
  function claimable(
    uint256 tokenId
  )
    external
    view
    returns (uint256 baseRewards, uint256 protocolRewards)
  {
    baseRewards = _claimableBaseRewards(tokenId);
    protocolRewards = _claimableProtocolRewards(tokenId);
  }

  /// @inheritdoc IStakingRewardsDistributor
  function pendingBaseRewards(
    uint256 tokenId
  ) external view returns (uint256 pendingRewards) {
    uint256 maxUserEpoch = staking.userPointEpoch(tokenId);
    if (maxUserEpoch == 0) return 0;

    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;

    for (
      uint256 periodId = 1;
      periodId <= currentPeriodId;
      periodId++
    ) {
      BaseRewardPeriod memory period = baseRewardPeriods[periodId];

      if (
        currentWeek < period.startWeek ||
        currentWeek >= period.endWeek
      ) continue;

      uint256 weeklyReward = baseRewardsPerWeek[periodId][
        currentWeek
      ];
      if (weeklyReward == 0) continue;

      uint256 balance = staking.balanceOfNFTAt(
        tokenId,
        block.timestamp
      );
      uint256 supply = staking.totalSupplyAt(block.timestamp);

      if (supply > 0) {
        pendingRewards += (balance * weeklyReward) / supply;
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingRewardsDistributor
  function claim(
    uint256 tokenId
  )
    external
    nonReentrant
    whenNotPaused
    notRestricted(msg.sender)
    returns (uint256 baseRewards, uint256 protocolRewards)
  {
    // Verify ownership or approval
    if (!staking.isApprovedOrOwner(msg.sender, tokenId))
      revert NotApprovedOrOwner();

    // Claim base rewards
    baseRewards = _claimBaseRewards(tokenId);

    // Claim protocol rewards
    protocolRewards = _claimProtocolRewards(tokenId);

    // Transfer total rewards
    uint256 totalRewards = baseRewards + protocolRewards;
    if (totalRewards > 0) {
      IERC20(token).safeTransfer(msg.sender, totalRewards);
    }
  }

  /// @inheritdoc IStakingRewardsDistributor
  function claimOnWithdrawal(
    uint256 tokenId,
    address to
  ) external nonReentrant whenNotPaused notRestricted(to) {
    // Verify access control
    if (msg.sender != address(staking)) revert OnlyStakingPositions();

    // Claim all rewards
    uint256 totalRewards = _claimBaseRewards(tokenId) +
      _claimProtocolRewards(tokenId);

    if (totalRewards > 0) {
      IERC20(token).safeTransfer(to, totalRewards);
    }
  }

  /// @inheritdoc IStakingRewardsDistributor
  function claimMany(
    uint256[] calldata tokenIds
  )
    external
    nonReentrant
    whenNotPaused
    notRestricted(msg.sender)
    returns (bool)
  {
    uint256 totalBaseRewards = 0;
    uint256 totalProtocolRewards = 0;

    for (uint256 i; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      if (tokenId == 0) break;

      // Verify ownership or approval
      if (!staking.isApprovedOrOwner(msg.sender, tokenId))
        revert NotApprovedOrOwner();

      // Claim rewards
      totalBaseRewards += _claimBaseRewards(tokenId);
      totalProtocolRewards += _claimProtocolRewards(tokenId);
    }

    // Transfer total rewards
    uint256 totalRewards = totalBaseRewards + totalProtocolRewards;
    if (totalRewards > 0) {
      IERC20(token).safeTransfer(msg.sender, totalRewards);
    }

    return true;
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  function _claimableBaseRewards(
    uint256 tokenId
  ) internal view returns (uint256) {
    uint256 maxUserEpoch = staking.userPointEpoch(tokenId);
    if (maxUserEpoch == 0) return 0;

    uint256 weekCursor = _getWeekCursor(tokenId);
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;

    if (weekCursor >= currentWeek) return 0;
    if (weekCursor < startTime) weekCursor = startTime;

    return
      _calculateRewardsForPeriods(tokenId, weekCursor, currentWeek);
  }

  function _getWeekCursor(
    uint256 tokenId
  ) internal view returns (uint256) {
    uint256 weekCursor = baseRewardCursor[tokenId];

    // If never claimed, start from token creation
    if (weekCursor == 0) {
      IStakingPositions.UserPoint memory userPoint = staking
        .getUserPointHistory(tokenId, 1);
      weekCursor = (userPoint.timestamp / WEEK) * WEEK;
    }

    return weekCursor;
  }

  function _calculateRewardsForPeriods(
    uint256 tokenId,
    uint256 weekCursor,
    uint256 currentWeek
  ) internal view returns (uint256) {
    uint256 totalClaimable = 0;
    uint256 startPeriodId = baseRewardPeriodCursor[tokenId];
    if (startPeriodId == 0) startPeriodId = 1;

    // Process up to 50 periods to avoid gas issues
    uint256 periodsProcessed = 0;
    for (
      uint256 periodId = startPeriodId;
      periodId <= currentPeriodId && periodsProcessed < 50;
      periodId++
    ) {
      BaseRewardPeriod memory period = baseRewardPeriods[periodId];

      // Skip if period hasn't started or cursor is past period end
      if (
        weekCursor >= period.endWeek ||
        currentWeek <= period.startWeek
      ) continue;

      periodsProcessed++;
      totalClaimable += _calculatePeriodRewards(
        tokenId,
        periodId,
        period,
        weekCursor,
        currentWeek
      );
    }

    return totalClaimable;
  }

  function _calculatePeriodRewards(
    uint256 tokenId,
    uint256 periodId,
    BaseRewardPeriod memory period,
    uint256 weekCursor,
    uint256 currentWeek
  ) internal view returns (uint256) {
    uint256 periodStart = Math.max(weekCursor, period.startWeek);
    uint256 periodEnd = Math.min(currentWeek, period.endWeek);
    uint256 periodRewards = 0;

    // Process up to 50 weeks to avoid gas issues
    uint256 weekCount = 0;
    for (
      uint256 week = periodStart;
      week < periodEnd && weekCount < 50;
      week += WEEK
    ) {
      uint256 weeklyReward = baseRewardsPerWeek[periodId][week];
      if (weeklyReward == 0) {
        weekCount++;
        continue;
      }

      uint256 balance = staking.balanceOfNFTAt(
        tokenId,
        week + WEEK - 1
      );
      uint256 supply = staking.totalSupplyAt(week + WEEK - 1);

      if (supply > 0) {
        periodRewards += (balance * weeklyReward) / supply;
      }
      weekCount++;
    }

    return periodRewards;
  }

  function _claimableProtocolRewards(
    uint256 tokenId
  ) internal view returns (uint256) {
    uint256 maxUserEpoch = staking.userPointEpoch(tokenId);
    if (maxUserEpoch == 0) return 0;

    // Use balanceOfNFTAt to bypass double vote protection
    uint256 currentBalance = staking.balanceOfNFTAt(
      tokenId,
      block.timestamp
    );
    uint256 rewardsPerTokenPaid = protocolRewardsPerTokenPaid[
      tokenId
    ];

    return
      (currentBalance *
        (cumulativeProtocolRewardsPerToken - rewardsPerTokenPaid)) /
      PRECISION;
  }

  function _claimBaseRewards(
    uint256 tokenId
  ) internal returns (uint256) {
    uint256 claimableAmount = _claimableBaseRewards(tokenId);

    // Update cursors based on what was actually processed
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    baseRewardCursor[tokenId] = currentWeek;

    // Only update period cursor to the last period we could fully process
    // This prevents skipping periods when we hit the 50-period limit
    uint256 startPeriodId = baseRewardPeriodCursor[tokenId];
    if (startPeriodId == 0) startPeriodId = 1;

    uint256 lastProcessedPeriod = Math.min(
      startPeriodId + 49, // Max 50 periods processed
      currentPeriodId
    );
    baseRewardPeriodCursor[tokenId] = lastProcessedPeriod;

    if (claimableAmount > 0) {
      emit BaseRewardsClaimed(
        tokenId,
        claimableAmount,
        baseRewardCursor[tokenId],
        currentWeek
      );
    }

    return claimableAmount;
  }

  function _claimProtocolRewards(
    uint256 tokenId
  ) internal returns (uint256) {
    uint256 claimableAmount = _claimableProtocolRewards(tokenId);

    if (claimableAmount > 0) {
      // Update the paid amount
      protocolRewardsPerTokenPaid[
        tokenId
      ] = cumulativeProtocolRewardsPerToken;

      emit ProtocolRewardsClaimed(tokenId, claimableAmount);
    }

    return claimableAmount;
  }

  /*//////////////////////////////////////////////////////////////
                          CALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingRewardsDistributor
  function onLockCreated(uint256 tokenId) external {
    if (msg.sender != address(staking)) revert OnlyStakingPositions();

    protocolRewardsPerTokenPaid[
      tokenId
    ] = cumulativeProtocolRewardsPerToken;
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingRewardsDistributor
  function updateAddresses(
    address staking_,
    address token_
  ) external onlyOwner {
    staking = IStakingPositions(staking_);
    token = token_;
  }

  /// @inheritdoc IStakingRewardsDistributor
  function depositBaseRewards(
    uint256 amount,
    uint256 duration
  ) external onlyOwner {
    if (amount == 0) revert ZeroAmount();
    if (duration == 0) revert ZeroDuration();

    // Transfer tokens from owner
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    // Create new reward period
    uint256 periodId = ++currentPeriodId;
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    uint256 weeklyAmount = amount / duration;

    baseRewardPeriods[periodId] = BaseRewardPeriod({
      startWeek: currentWeek,
      endWeek: currentWeek + (duration * WEEK),
      totalAmount: amount,
      weeklyAmount: weeklyAmount
    });

    // Distribute rewards across weeks
    for (uint256 i; i < duration; i++) {
      uint256 week = currentWeek + (i * WEEK);
      baseRewardsPerWeek[periodId][week] = weeklyAmount;
    }

    // Handle remainder
    uint256 remainder = amount - (weeklyAmount * duration);
    if (remainder > 0) {
      baseRewardsPerWeek[periodId][currentWeek] += remainder;
    }

    emit BaseRewardsDeposited(
      periodId,
      amount,
      currentWeek,
      duration,
      weeklyAmount
    );
  }

  /// @inheritdoc IStakingRewardsDistributor
  function depositProtocolFees(uint256 amount) external onlyOwner {
    if (amount == 0) revert ZeroAmount();

    // Transfer tokens from owner
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    // Get current total voting power
    uint256 totalSupply = staking.totalSupply();

    if (totalSupply > 0) {
      // Add to cumulative rewards per token
      cumulativeProtocolRewardsPerToken +=
        (amount * PRECISION) /
        totalSupply;
    }

    emit ProtocolFeesDeposited(amount, block.timestamp, totalSupply);
  }
}
