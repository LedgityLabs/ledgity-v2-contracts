// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";
import { IStakingRewardsDistributor } from "src/protocol-v2/interfaces/IStakingRewardsDistributor.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract StakingIntegration_Test is Test, Fixtures {
  uint256 public constant WEEK = 7 * 86400;
  uint256 public constant TEST_AMOUNT = 1000 * 1e18;
  uint256 public constant TEST_LOCK_DURATION = 52 * WEEK; // 1 year
  uint256 public constant REWARD_AMOUNT = 100 * 1e18;

  function setUp() public {
    _setUp();
    _setupUsers();
  }

  function _setupUsers() internal {
    // Mint tokens to test users and owner
    for (uint256 i = 0; i < users.length; i++) {
      deal(address(ldyToken), users[i], INITIAL_BALANCE);
      vm.prank(users[i]);
      ldyToken.approve(address(stakingPositions), type(uint256).max);
    }

    // Mint tokens to the actual owner for rewards
    deal(address(ldyToken), globalOwner.owner(), INITIAL_BALANCE);
    vm.prank(globalOwner.owner());
    ldyToken.approve(
      address(stakingRewardsDistributor),
      type(uint256).max
    );
  }

  /*//////////////////////////////////////////////////////////////
                    STAKING POSITIONS + REWARDS INTEGRATION
    //////////////////////////////////////////////////////////////*/

  function test_Integration_ClaimOnWithdrawal_Success() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit both types of rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 2);

    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Fast forward 1 week
    vm.warp(block.timestamp + WEEK);

    // Check claimable amounts before withdrawal
    (
      uint256 baseRewardsBefore,
      uint256 protocolRewardsBefore
    ) = stakingRewardsDistributor.claimable(tokenId);

    uint256 expectedTotal = baseRewardsBefore + protocolRewardsBefore;
    uint256 initialBalance = ldyToken.balanceOf(testAccount2);

    // Simulate withdrawal process - StakingPositions calls claimOnWithdrawal
    vm.prank(address(stakingPositions));
    stakingRewardsDistributor.claimOnWithdrawal(tokenId, testAccount2);

    // Check that rewards were transferred to testAccount2
    assertEq(
      ldyToken.balanceOf(testAccount2),
      initialBalance + expectedTotal
    );

    // Check that claimable amounts are now zero
    (
      uint256 baseRewardsAfter,
      uint256 protocolRewardsAfter
    ) = stakingRewardsDistributor.claimable(tokenId);

    assertEq(baseRewardsAfter, 0);
    assertEq(protocolRewardsAfter, 0);
  }

  function test_Integration_CompleteRewardCycle() public {
    // Create staking positions with different lock durations
    vm.prank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.prank(testAccount2);
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION / 2
    );

    // Deposit base rewards for 4 weeks
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 4);

    // Fast forward 2 weeks and deposit protocol fees
    vm.warp(block.timestamp + 2 * WEEK);

    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Fast forward another 2 weeks
    vm.warp(block.timestamp + 2 * WEEK);

    // Claim rewards for both users
    uint256 balance1Before = ldyToken.balanceOf(testAccount1);
    uint256 balance2Before = ldyToken.balanceOf(testAccount2);

    vm.prank(testAccount1);
    (
      uint256 baseRewards1,
      uint256 protocolRewards1
    ) = stakingRewardsDistributor.claim(tokenId1);

    vm.prank(testAccount2);
    (
      uint256 baseRewards2,
      uint256 protocolRewards2
    ) = stakingRewardsDistributor.claim(tokenId2);

    // Check that rewards were distributed
    assertGt(baseRewards1, 0);
    assertGt(protocolRewards1, 0);
    assertGt(baseRewards2, 0);
    assertGt(protocolRewards2, 0);

    // Check that tokens were transferred
    assertEq(
      ldyToken.balanceOf(testAccount1),
      balance1Before + baseRewards1 + protocolRewards1
    );
    assertEq(
      ldyToken.balanceOf(testAccount2),
      balance2Before + baseRewards2 + protocolRewards2
    );

    // User1 should get more rewards due to longer lock
    assertGt(
      baseRewards1 + protocolRewards1,
      baseRewards2 + protocolRewards2
    );
  }

  function test_Integration_RewardsAfterLockExpiry() public {
    // Create short lock
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, WEEK);

    // Deposit base rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 4);

    // Fast forward past lock expiry
    vm.warp(block.timestamp + 2 * WEEK);

    // Should still be able to claim rewards earned before expiry
    vm.prank(testAccount1);
    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claim(tokenId);

    assertGt(baseRewards, 0);
    assertEq(protocolRewards, 0); // No protocol fees deposited
  }

  function test_Integration_MultipleClaimsSameToken() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit base rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 4);

    // Fast forward 1 week and claim
    vm.warp(block.timestamp + WEEK);

    vm.prank(testAccount1);
    (uint256 baseRewards1, ) = stakingRewardsDistributor.claim(
      tokenId
    );

    // Fast forward another week and claim again
    vm.warp(block.timestamp + WEEK);

    vm.prank(testAccount1);
    (uint256 baseRewards2, ) = stakingRewardsDistributor.claim(
      tokenId
    );

    // Both claims should yield rewards
    assertGt(baseRewards1, 0);
    assertGt(baseRewards2, 0);

    // Second claim should be for different period
    assertApproxEqRel(baseRewards1, baseRewards2, 0.1e18); // Should be similar amounts
  }

  function test_Integration_StakingPositionsOwnershipAndRewards() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit protocol fees
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Approve testAccount2 to manage the NFT
    vm.prank(testAccount1);
    stakingPositions.approve(testAccount2, tokenId);

    // testAccount2 should be able to claim rewards
    vm.prank(testAccount2);
    (, uint256 protocolRewards) = stakingRewardsDistributor.claim(
      tokenId
    );

    // Rewards should go to testAccount2 (the claimer)
    assertGt(protocolRewards, 0);
    assertGt(ldyToken.balanceOf(testAccount2), 0);
  }

  function test_Integration_TransferNFTAndRewardRights() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit protocol fees
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Transfer NFT to testAccount2
    vm.prank(testAccount1);
    stakingPositions.transferFrom(testAccount1, testAccount2, tokenId);

    // testAccount2 should now be able to claim rewards
    vm.prank(testAccount2);
    (, uint256 protocolRewards) = stakingRewardsDistributor.claim(
      tokenId
    );

    assertGt(protocolRewards, 0);

    // testAccount1 should no longer be able to claim
    vm.startPrank(testAccount1);
    vm.expectRevert(
      IStakingRewardsDistributor.NotApprovedOrOwner.selector
    );
    stakingRewardsDistributor.claim(tokenId);
    vm.stopPrank();
  }

  function test_Integration_RewardsProportionalToVotingPower() public {
    // Create two staking positions with different voting power
    vm.prank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.prank(testAccount2);
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT * 2, // Double the amount
      TEST_LOCK_DURATION
    );

    // Deposit both base and protocol rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 2);

    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Fast forward 1 week
    vm.warp(block.timestamp + WEEK);

    // Claim rewards for both
    vm.prank(testAccount1);
    (
      uint256 baseRewards1,
      uint256 protocolRewards1
    ) = stakingRewardsDistributor.claim(tokenId1);

    vm.prank(testAccount2);
    (
      uint256 baseRewards2,
      uint256 protocolRewards2
    ) = stakingRewardsDistributor.claim(tokenId2);

    // User2 should get approximately twice the rewards (due to 2x stake)
    assertGt(baseRewards2, baseRewards1);
    assertGt(protocolRewards2, protocolRewards1);
    assertApproxEqRel(baseRewards2, baseRewards1 * 2, 0.01e18); // 1% tolerance
    assertApproxEqRel(protocolRewards2, protocolRewards1 * 2, 0.01e18); // 1% tolerance
  }

  function test_Integration_ClaimManyWithMultiplePositions() public {
    // Create multiple staking positions for testAccount1
    vm.startPrank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );
    vm.stopPrank();

    // Deposit rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Claim for multiple tokens
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;

    uint256 initialBalance = ldyToken.balanceOf(testAccount1);

    vm.prank(testAccount1);
    bool success = stakingRewardsDistributor.claimMany(tokenIds);

    assertTrue(success);
    assertGt(ldyToken.balanceOf(testAccount1), initialBalance);
  }

  /*//////////////////////////////////////////////////////////////
                        EDGE CASES AND ERROR CONDITIONS
    //////////////////////////////////////////////////////////////*/

  function test_Integration_ClaimWithZeroVotingPower() public {
    // Create and immediately expire lock
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, WEEK);

    // Fast forward past expiry
    vm.warp(block.timestamp + WEEK + 1);

    // Deposit protocol fees
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // Try to claim - should get 0 protocol rewards due to 0 voting power
    vm.prank(testAccount1);
    (, uint256 protocolRewards) = stakingRewardsDistributor.claim(
      tokenId
    );

    assertEq(protocolRewards, 0);
  }

  function test_Integration_LargeNumberOfPeriods() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Create many small reward periods (test gas limits)
    for (uint256 i = 0; i < 10; i++) {
      vm.prank(globalOwner.owner());
      stakingRewardsDistributor.depositBaseRewards(
        REWARD_AMOUNT / 10,
        1
      );
      vm.warp(block.timestamp + WEEK);
    }

    // Should be able to claim without running out of gas
    vm.prank(testAccount1);
    (uint256 baseRewards, ) = stakingRewardsDistributor.claim(
      tokenId
    );

    assertGt(baseRewards, 0);
  }

  function test_Integration_ProtocolRewardsOnlyForCurrentStakers() public {
    // Deposit protocol fees before any staking
    uint256 feeAmount = REWARD_AMOUNT;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    // Create staking position after fees deposited
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Claim rewards - should get nothing from the first deposit
    vm.prank(testAccount1);
    (, uint256 protocolRewards) = stakingRewardsDistributor.claim(
      tokenId
    );

    assertEq(protocolRewards, 0);

    // Deposit more fees after staking
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    // Now should be able to claim
    vm.prank(testAccount1);
    (, uint256 protocolRewards2) = stakingRewardsDistributor.claim(
      tokenId
    );

    assertGt(protocolRewards2, 0);
  }
}
