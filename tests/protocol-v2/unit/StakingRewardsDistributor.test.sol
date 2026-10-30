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

    // Mint tokens to the actual owner (not the globalOwner contract) for rewards
    deal(address(ldyToken), globalOwner.owner(), INITIAL_BALANCE);
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

    vm.startPrank(globalOwner.owner());

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
    vm.startPrank(globalOwner.owner());

    vm.expectRevert(IStakingRewardsDistributor.ZeroAmount.selector);
    stakingRewardsDistributor.depositBaseRewards(0, 4);

    vm.stopPrank();
  }

  function test_DepositBaseRewards_RevertZeroDuration() public {
    vm.startPrank(globalOwner.owner());

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


  /*//////////////////////////////////////////////////////////////
                            PROTOCOL FEE REWARDS TESTS
    //////////////////////////////////////////////////////////////*/

  function test_DepositProtocolFees_Success() public {
    // This is a unit test focusing on the distributor logic with zero total supply
    uint256 feeAmount = REWARD_AMOUNT;

    vm.startPrank(globalOwner.owner());

    // Since this is a unit test, we test the zero total supply case
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    vm.stopPrank();

    // With zero total supply, cumulative rewards should remain 0
    assertEq(
      stakingRewardsDistributor.cumulativeProtocolRewardsPerToken(),
      0
    );
  }

  function test_DepositProtocolFees_ZeroTotalSupply() public {
    // No staking positions created, so total supply is 0
    uint256 feeAmount = REWARD_AMOUNT;

    vm.startPrank(globalOwner.owner());

    // Should not revert but also not update cumulative rewards
    stakingRewardsDistributor.depositProtocolFees(feeAmount);

    vm.stopPrank();

    assertEq(
      stakingRewardsDistributor.cumulativeProtocolRewardsPerToken(),
      0
    );
  }

  function test_DepositProtocolFees_RevertZeroAmount() public {
    vm.startPrank(globalOwner.owner());

    vm.expectRevert(IStakingRewardsDistributor.ZeroAmount.selector);
    stakingRewardsDistributor.depositProtocolFees(0);

    vm.stopPrank();
  }



  /*//////////////////////////////////////////////////////////////
                        UNIT TESTS FOR ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

  function test_ClaimOnWithdrawal_RevertNotStakingPositions() public {
    // Test access control without creating staking positions
    // This is a pure unit test of the access control mechanism
    vm.startPrank(testAccount1);

    vm.expectRevert(
      IStakingRewardsDistributor.OnlyStakingPositions.selector
    );
    stakingRewardsDistributor.claimOnWithdrawal(1, testAccount1);

    vm.stopPrank();
  }

  function test_ClaimOnWithdrawal_RevertNotStakingPositionsEvenAsOwner() public {
    // Test that even the owner cannot bypass access control
    vm.startPrank(globalOwner.owner());

    vm.expectRevert(
      IStakingRewardsDistributor.OnlyStakingPositions.selector
    );
    stakingRewardsDistributor.claimOnWithdrawal(1, testAccount1);

    vm.stopPrank();
  }

  function test_ClaimOnWithdrawal_RevertNotStakingPositionsEvenAsDeployer() public {
    // Test that even the deployer cannot bypass access control
    vm.expectRevert(
      IStakingRewardsDistributor.OnlyStakingPositions.selector
    );
    stakingRewardsDistributor.claimOnWithdrawal(1, testAccount1);
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Claimable_ZeroForNonExistentToken() public view {
    // Test claimable function with non-existent token
    // This is a pure unit test that doesn't require staking positions
    (
      uint256 baseRewards,
      uint256 protocolRewards
    ) = stakingRewardsDistributor.claimable(999);

    assertEq(baseRewards, 0);
    assertEq(protocolRewards, 0);
  }


  /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/


  /// @dev Claims until the token's week cursor reaches the current week, as a user would
  function _claimAll(
    address user,
    uint256 tokenId
  ) internal returns (uint256 total) {
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    for (uint256 i; i < 10; i++) {
      vm.prank(user);
      (uint256 base, ) = stakingRewardsDistributor.claim(tokenId);
      total += base;
      if (stakingRewardsDistributor.baseRewardCursor(tokenId) >= currentWeek)
        break;
    }
  }

  function test_BaseRewards_NoDoubleCountAfterFiftyWeeks() public {
    // A sole staker locks, a period starts three weeks later and the staker does not
    // claim for 60 weeks: each week of the period must be paid exactly once
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      4 * 52 * WEEK
    );

    vm.warp(block.timestamp + 3 * WEEK);
    uint256 periodStart = (block.timestamp / WEEK) * WEEK;
    uint256 weekly = 10 * 1e18;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(weekly * 100, 100);

    vm.warp(block.timestamp + 60 * WEEK);
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    uint256 weeksElapsed = (currentWeek - periodStart) / WEEK;

    uint256 paid = _claimAll(testAccount1, tokenId);

    // Sole staker: the whole weekly amount of every elapsed week, and not one week more
    assertLe(paid, weeksElapsed * weekly, "a week was paid twice");
    assertApproxEqRel(paid, weeksElapsed * weekly, 1e12);

    // Nothing left to claim this week
    (uint256 claimableBase, ) = stakingRewardsDistributor.claimable(
      tokenId
    );
    assertEq(claimableBase, 0);
  }

  function test_BaseRewards_OverlappingPeriodsBothPaidInFull() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      4 * 52 * WEEK
    );

    // Period 1: 20 weeks. Period 2 starts 5 weeks later for 4 weeks.
    uint256 amount1 = 20 * 1e18;
    uint256 amount2 = 8 * 1e18;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(amount1, 20);
    vm.warp(block.timestamp + 5 * WEEK);
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(amount2, 4);

    // Claims while both run, after period 2 ends, and after period 1 ends
    uint256 paid;
    vm.warp(block.timestamp + 2 * WEEK);
    paid += _claimAll(testAccount1, tokenId);
    vm.warp(block.timestamp + 4 * WEEK);
    paid += _claimAll(testAccount1, tokenId);
    vm.warp(block.timestamp + 20 * WEEK);
    paid += _claimAll(testAccount1, tokenId);

    // Sole staker over both periods: everything distributed is paid, nothing twice
    assertLe(paid, amount1 + amount2);
    assertApproxEqRel(paid, amount1 + amount2, 1e12);
    // Both periods ended: the cursor moved past them
    assertEq(stakingRewardsDistributor.baseRewardPeriodCursor(tokenId), 3);
  }

  function test_BaseRewards_TwoStakersNeverOverpaid() public {
    vm.prank(testAccount1);
    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      4 * 52 * WEEK
    );
    vm.prank(testAccount2);
    uint256 tokenId2 = stakingPositions.createLock(
      3 * TEST_AMOUNT,
      2 * 52 * WEEK
    );

    vm.warp(block.timestamp + WEEK);
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(60 * 1e18, 60);
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(30 * 1e18, 30);

    // One claims every 10 weeks, the other only once at the end (past 50 weeks)
    uint256 paid;
    for (uint256 i; i < 7; i++) {
      vm.warp(block.timestamp + 10 * WEEK);
      paid += _claimAll(testAccount1, tokenId1);
    }
    paid += _claimAll(testAccount2, tokenId2);

    assertLe(paid, 90 * 1e18, "distributor over-paid");
    assertApproxEqRel(paid, 90 * 1e18, 1e12);
  }

  function test_KnownLimitation_WithdrawAfterLongGapPaysOneWindowOnly() public {
    // A sole staker never claims, then withdraws 104 weeks later: withdraw() pays one
    // claim window (50 weeks) and burns the position, the remaining weeks stay unclaimable
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, 104 * WEEK);
    vm.warp(block.timestamp + WEEK);
    uint256 weekly = 10 * 1e18;
    vm.prank(globalOwner.owner());
    stakingRewardsDistributor.depositBaseRewards(weekly * 100, 100);

    vm.warp(block.timestamp + 104 * WEEK);
    uint256 before = ldyToken.balanceOf(testAccount1);
    vm.prank(testAccount1);
    stakingPositions.withdraw(tokenId);
    uint256 rewards = ldyToken.balanceOf(testAccount1) - before - TEST_AMOUNT;

    // At most one 50-week window paid out of about 100 weeks owed
    assertLe(rewards, 50 * weekly, "more than one window paid");
    emit log_named_uint("rewards paid on withdrawal (LDY)", rewards / 1e18);
    emit log_named_uint("rewards left unclaimable (LDY)", ldyToken.balanceOf(address(stakingRewardsDistributor)) / 1e18);
  }

  function test_Gas_WorstCaseClaim() public {
    // 30 overlapping periods and a 50-week window: the heaviest claim the code allows
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, 4 * 52 * WEEK);
    vm.prank(testAccount2);
    stakingPositions.createLock(TEST_AMOUNT, 3 * 52 * WEEK);
    for (uint256 i; i < 30; i++) {
      vm.prank(globalOwner.owner());
      stakingRewardsDistributor.depositBaseRewards(60 * 1e18, 60);
    }
    vm.warp(block.timestamp + 60 * WEEK);

    vm.prank(testAccount1);
    uint256 gasBefore = gasleft();
    stakingRewardsDistributor.claim(tokenId);
    uint256 used = gasBefore - gasleft();
    emit log_named_uint("worst-case claim gas", used);
    // EIP-7825 (Fusaka, Dec 2025): no transaction may use more than 2^24 gas
    assertLt(used, 16_777_216, "claim above the per-transaction gas cap");
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
