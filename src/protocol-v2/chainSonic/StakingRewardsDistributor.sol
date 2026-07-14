// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
// Libraries
import { SonicFeeMRegister } from "src/protocol-v2/chainSonic/SonicFeeMRegister.sol";

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
 * @notice This contract extends StakingRewardsDistributor and adds Sonic FeeM registration functionality
 */
contract StakingRewardsDistributorSonic is StakingRewardsDistributor {
  /// @dev Re-init is blocked by OZ's `initializer` modifier on the parent `initialize()`.
  function initializeAndRegister(
    address staking_,
    address globalOwner_,
    address globalPause_,
    address globalAccessList_
  ) public {
    /// @dev FeeM registration was under maintenance during deploy
    // SonicFeeMRegister.registerContract();
    StakingRewardsDistributor.initialize(
      staking_,
      globalOwner_,
      globalPause_,
      globalAccessList_
    );
  }
}
