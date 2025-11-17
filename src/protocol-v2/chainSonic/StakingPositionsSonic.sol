// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
// Libraries
import { SonicFeeMRegister } from "src/protocol-v2/chainSonic/SonicFeeMRegister.sol";

/**
 * @title Ledgity Staking Positions
 * @notice Staking position NFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
 * @notice Voting power has a weight depending on time, so that users are committed to the future of the protocol
 * @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
 * @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
 * @author Modified from Velodrome (https://github.com/velodrome-finance/contracts/blob/main/contracts/VotingEscrow.sol)
 * @author Ledgity, vBlackwhale (https://github.com/vblackwhale)
 *
 * @dev Vote weight decays linearly over time. Lock time cannot be more than `maxTime` (configurable, default 4 years).
 * @notice This contract extends StakingPositions and adds Sonic FeeM registration functionality
 */
contract StakingPositionsSonic is StakingPositions {
  function initializeAndRegister(
    address token_,
    address rewardsDistributor_,
    uint256 maxTime_,
    address globalOwner_,
    address globalPause_,
    address globalAccessList_
  ) public {
    SonicFeeMRegister.registerContract();
    StakingPositions.initialize(
      token_,
      rewardsDistributor_,
      maxTime_,
      globalOwner_,
      globalPause_,
      globalAccessList_
    );
  }
}
