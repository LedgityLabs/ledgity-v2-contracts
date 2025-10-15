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
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingRewardsDistributor_UnitTest is Test, Fixtures {
  uint256 public constant WEEK = 7 * 86400;
  uint256 public constant TEST_AMOUNT = 1000 * 1e18;
  uint256 public constant TEST_LOCK_DURATION = 52 * WEEK; // 1 year
  uint256 public constant REWARD_AMOUNT = 100 * 1e18;
  uint256 public constant PRECISION = 1e18;

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

    // Mint tokens to owner for rewards
    deal(address(ldyToken), address(globalOwner), INITIAL_BALANCE);
    vm.prank(globalOwner.owner());
    ldyToken.approve(
      address(stakingRewardsDistributor),
      type(uint256).max
    );
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Initialize() public view {
    assertEq(
      address(stakingRewardsDistributor.staking()),
      address(stakingPositions)
    );
    assertEq(stakingRewardsDistributor.token(), address(ldyToken));
    assertEq(stakingRewardsDistributor.currentPeriodId(), 0);
    assertEq(
      stakingRewardsDistributor.cumulativeProtocolRewardsPerToken(),
      0
    );

    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    assertEq(stakingRewardsDistributor.startTime(), currentWeek);
    assertEq(stakingRewardsDistributor.lastTokenTime(), currentWeek);
  }

  /*//////////////////////////////////////////////////////////////
                            BASE REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

  function test_DepositBaseRewards_Success() public {
    uint256 amount = REWARD_AMOUNT;
    uint256 duration = 4; // 4 weeks
    uint256 weeklyAmount = amount / duration;
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;

    vm.startPrank(address(globalOwner));

    vm.expectEmit(true, true, true, true);
    emit BaseRewardsDeposited(
      1,
      amount,
      currentWeek,
      duration,
      weeklyAmount
    );

    stakingRewardsDistributor.depositBaseRewards(amount, duration);

    vm.stopPrank();

    assertEq(stakingRewardsDistributor.currentPeriodId(), 1);

    // Check weekly rewards are set correctly
    for (uint256 i = 0; i < duration; i++) {
      uint256 week = currentWeek + (i * WEEK);
      assertEq(
        stakingRewardsDistributor.baseRewardsPerWeek(1, week),
        weeklyAmount
      );
    }

    // Check remainder is added to first week
    uint256 remainder = amount - (weeklyAmount * duration);
    if (remainder > 0) {
      assertEq(
        stakingRewardsDistributor.baseRewardsPerWeek(1, currentWeek),
        weeklyAmount + remainder
      );
    }
  }

  function test_DepositBaseRewards_RevertZeroAmount() public {
    vm.startPrank(address(globalOwner));

    vm.expectRevert(IStakingRewardsDistributor.ZeroAmount.selector);
    stakingRewardsDistributor.depositBaseRewards(0, 4);

    vm.stopPrank();
  }

  function test_DepositBaseRewards_RevertZeroDuration() public {
    vm.startPrank(address(globalOwner));

    vm.expectRevert(IStakingRewardsDistributor.ZeroDuration.selector);
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 0);

    vm.stopPrank();
  }

  function test_DepositBaseRewards_RevertNotOwner() public {
    vm.startPrank(testAccount1);

    vm.expectRevert();
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 4);

    vm.stopPrank();
  }

  function test_BaseRewards_ClaimSinglePeriod() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit base rewards
    uint256 rewardAmount = REWARD_AMOUNT;
    uint256 duration = 2; // 2 weeks

    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(
      rewardAmount,
      duration
    );

    // Fast forward 1 week
    vm.warp(block.timestamp + WEEK);

    // Claim rewards
    vm.startPrank(testAccount1);

    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claim(tokenId);

    vm.stopPrank();

    assertGt(baseRewards, 0);
    assertEq(protocolRewards, 0);

    // Check that cursor is updated
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    assertEq(
      stakingRewardsDistributor.baseRewardCursor(tokenId),
      currentWeek
    );
  }

  function test_BaseRewards_ClaimMultiplePeriods() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit first period
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 2);

    // Fast forward 1 week
    vm.warp(block.timestamp + WEEK);

    // Deposit second period
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 2);

    // Fast forward another week
    vm.warp(block.timestamp + WEEK);

    // Claim rewards
    vm.startPrank(testAccount1);

    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claim(tokenId);

    vm.stopPrank();

    assertGt(baseRewards, 0);
    assertEq(protocolRewards, 0);
  }

  function test_BaseRewards_ProportionalToVotingPower() public {
    // Create two staking positions with different amounts
    vm.prank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.prank(testAccount2);
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT * 2,
      TEST_LOCK_DURATION
    );

    // Deposit base rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(REWARD_AMOUNT, 2);

    // Fast forward 1 week
    vm.warp(block.timestamp + WEEK);

    // Claim rewards for both
    vm.prank(testAccount1);
    (uint256 baseRewards1, ) = stakingRewardsDistributor.claim(
      tokenId1
    );

    vm.prank(testAccount2);
    (uint256 baseRewards2, ) = stakingRewardsDistributor.claim(
      tokenId2
    );

    // User2 should get approximately twice the rewards (due to 2x stake)
    assertGt(baseRewards2, baseRewards1);
    assertApproxEqRel(baseRewards2, baseRewards1 * 2, 0.01e18); // 1% tolerance
  }

  /*//////////////////////////////////////////////////////////////
                            PROTOCOL FEE REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

  function test_DepositProtocolFees_Success() public {
    // Create staking position first to have total supply > 0
    vm.prank(testAccount1);
    stakingPositions.createLock(TEST_AMOUNT, TEST_LOCK_DURATION);

    uint256 feeAmount = REWARD_AMOUNT;
    uint256 totalSupply = stakingPositions.totalSupply();

    vm.startPrank(address(globalOwner));

    vm.expectEmit(true, true, true, true);
    emit ProtocolFeesDeposited(
      feeAmount,
      block.timestamp,
      totalSupply
    );

    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    vm.stopPrank();

    uint256 expectedRewardsPerToken = (feeAmount * PRECISION) /
      totalSupply;
    assertEq(
      stakingRewardsDistributor.cumulativeProtocolRewardsPerToken(),
      expectedRewardsPerToken
    );
  }

  function test_DepositProtocolFees_ZeroTotalSupply() public {
    // No staking positions created, so total supply is 0
    uint256 feeAmount = REWARD_AMOUNT;

    vm.startPrank(address(globalOwner));

    // Should not revert but also not update cumulative rewards
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    vm.stopPrank();

    assertEq(
      stakingRewardsDistributor.cumulativeProtocolRewardsPerToken(),
      0
    );
  }

  function test_DepositProtocolFees_RevertZeroAmount() public {
    vm.startPrank(address(globalOwner));

    vm.expectRevert(IStakingRewardsDistributor.ZeroAmount.selector);
    stakingRewardsDistributor.depositProtocolFees(0);

    vm.stopPrank();
  }

  function test_ProtocolRewards_ClaimAfterDeposit() public {
    // Create staking position
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Deposit protocol fees
    uint256 feeAmount = REWARD_AMOUNT;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    // Claim rewards
    vm.startPrank(testAccount1);

    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claim(tokenId);

    vm.stopPrank();

    assertEq(baseRewards, 0);
    assertGt(protocolRewards, 0);

    // Should get all the protocol fees since they're the only staker
    assertApproxEqRel(protocolRewards, feeAmount, 0.01e18); // 1% tolerance
  }

  function test_ProtocolRewards_ProportionalToVotingPower() public {
    // Create two staking positions with different voting power
    vm.prank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.prank(testAccount2);
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT * 2,
      TEST_LOCK_DURATION
    );

    // Deposit protocol fees
    uint256 feeAmount = REWARD_AMOUNT;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    // Claim rewards for both
    vm.prank(testAccount1);
    (, uint256 protocolRewards1) = stakingRewardsDistributor.claim(
      tokenId1
    );

    vm.prank(testAccount2);
    (, uint256 protocolRewards2) = stakingRewardsDistributor.claim(
      tokenId2
    );

    // User2 should get approximately twice the rewards
    assertGt(protocolRewards2, protocolRewards1);
    assertApproxEqRel(
      protocolRewards2,
      protocolRewards1 * 2,
      0.01e18
    ); // 1% tolerance
  }

  function test_ProtocolRewards_OnlyForCurrentStakers() public {
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

  /*//////////////////////////////////////////////////////////////
                            CLAIM FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Claim_RevertNotApprovedOrOwner() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount2);

    vm.expectRevert(
      IStakingRewardsDistributor.NotApprovedOrOwner.selector
    );
    stakingRewardsDistributor.claim(tokenId);

    vm.stopPrank();
  }

  function test_Claim_WithApproval() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Approve testAccount2
    vm.prank(testAccount1);
    stakingPositions.approve(testAccount2, tokenId);

    // Deposit some rewards
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositProtocolFees(REWARD_AMOUNT);

    // testAccount2 should be able to claim
    vm.startPrank(testAccount2);

    (, uint256 protocolRewards) = stakingRewardsDistributor.claim(
      tokenId
    );

    vm.stopPrank();

    // Rewards should go to testAccount2 (the claimer)
    assertGt(protocolRewards, 0);
  }

  function test_ClaimMany_Success() public {
    // Create multiple staking positions
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

  function test_ClaimMany_PartialOwnership() public {
    // testAccount1 creates tokens
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

    // testAccount2 creates a token
    vm.prank(testAccount2);
    uint256 tokenId3 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Try to claim for all tokens as testAccount1 (should fail for tokenId3)
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = tokenId1;
    tokenIds[1] = tokenId2;
    tokenIds[2] = tokenId3;

    vm.startPrank(testAccount1);

    vm.expectRevert(
      IStakingRewardsDistributor.NotApprovedOrOwner.selector
    );
    stakingRewardsDistributor.claimMany(tokenIds);

    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Claimable_BothRewardTypes() public {
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

    // Check claimable amounts
    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claimable(tokenId);

    assertGt(baseRewards, 0);
    assertGt(protocolRewards, 0);
  }

  function test_Claimable_ZeroForNonExistentToken() public view {
    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claimable(999);

    assertEq(baseRewards, 0);
    assertEq(protocolRewards, 0);
  }

  /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

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

  /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

  function test_EdgeCase_ClaimWithZeroVotingPower() public {
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

  function test_EdgeCase_LargeNumberOfPeriods() public {
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

  function test_EdgeCase_RewardRemainder() public {
    // Test that remainder is properly handled when amount doesn't divide evenly
    uint256 amount = 1000; // Amount that doesn't divide evenly by 3
    uint256 duration = 3;
    uint256 expectedWeeklyAmount = amount / duration; // 333
    uint256 expectedRemainder = amount % duration; // 1

    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(amount, duration);

    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;

    // First week should have weekly amount + remainder
    assertEq(
      stakingRewardsDistributor.baseRewardsPerWeek(1, currentWeek),
      expectedWeeklyAmount + expectedRemainder
    );

    // Other weeks should have just weekly amount
    assertEq(
      stakingRewardsDistributor.baseRewardsPerWeek(
        1,
        currentWeek + WEEK
      ),
      expectedWeeklyAmount
    );
    assertEq(
      stakingRewardsDistributor.baseRewardsPerWeek(
        1,
        currentWeek + 2 * WEEK
      ),
      expectedWeeklyAmount
    );
  }
}
