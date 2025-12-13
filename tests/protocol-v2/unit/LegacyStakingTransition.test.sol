// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Contracts
import { LegacyStakingTransition } from "src/protocol-v2/staking/LegacyStakingTransition.sol";
import { GlobalOwner } from "src/protocol-v1/GlobalOwner.sol";
import { GlobalPause } from "src/protocol-v1/GlobalPause.sol";
import { GlobalBlacklist } from "src/protocol-v1/GlobalBlacklist.sol";
import { GenericERC20 } from "src/protocol-v1/GenericERC20.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LegacyStakingTransition_UnitTest is Test {
  uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
  uint256 public constant TEST_AMOUNT = 1000 * 1e18;
  uint256 public constant REWARD_AMOUNT = 100 * 1e18;
  uint256 public constant WEEK = 7 * 86400;

  GlobalOwner internal globalOwner;
  GlobalPause internal globalPause;
  GlobalBlacklist internal globalBlacklist;
  GenericERC20 internal ldyToken;
  LegacyStakingTransition internal legacyStaking;

  address internal testAccount1 = address(0xA11CE);
  address internal testAccount2 = address(0xB0B);
  address internal owner;

  LegacyStakingTransition.StakeDurationInfo[]
    internal stakeDurationInfos;

  event EarlyWithdrawalsToggled(bool enabled);
  event UndistributedRewardsWithdrawn(uint256 amount);
  event Unstaked(
    address indexed user,
    uint256 stakeIndex,
    uint256 amount
  );

  function setUp() public {
    owner = address(this);

    // Deploy token
    ldyToken = new GenericERC20("Ledgity Token", "LDY", 18);

    // Deploy global contracts
    GlobalOwner globalOwnerImpl = new GlobalOwner();
    GlobalPause globalPauseImpl = new GlobalPause();
    GlobalBlacklist globalBlacklistImpl = new GlobalBlacklist();
    LegacyStakingTransition legacyStakingImpl = new LegacyStakingTransition();

    // Deploy proxies
    ERC1967Proxy globalOwnerProxy = new ERC1967Proxy(
      address(globalOwnerImpl),
      ""
    );
    ERC1967Proxy globalPauseProxy = new ERC1967Proxy(
      address(globalPauseImpl),
      ""
    );
    ERC1967Proxy globalBlacklistProxy = new ERC1967Proxy(
      address(globalBlacklistImpl),
      ""
    );
    ERC1967Proxy legacyStakingProxy = new ERC1967Proxy(
      address(legacyStakingImpl),
      ""
    );

    globalOwner = GlobalOwner(address(globalOwnerProxy));
    globalPause = GlobalPause(address(globalPauseProxy));
    globalBlacklist = GlobalBlacklist(address(globalBlacklistProxy));
    legacyStaking = LegacyStakingTransition(
      address(legacyStakingProxy)
    );

    // Initialize global contracts
    globalOwner.initialize();
    globalPause.initialize(address(globalOwner));
    globalBlacklist.initialize(address(globalOwner));

    // Setup stake duration infos
    stakeDurationInfos.push(
      LegacyStakingTransition.StakeDurationInfo(0, 10000)
    );
    stakeDurationInfos.push(
      LegacyStakingTransition.StakeDurationInfo(30 days, 10000)
    );
    stakeDurationInfos.push(
      LegacyStakingTransition.StakeDurationInfo(365 days, 15000)
    );

    // Initialize legacy staking
    legacyStaking.initialize(
      address(globalOwner),
      address(globalPause),
      address(globalBlacklist),
      address(ldyToken),
      stakeDurationInfos,
      30 days,
      100 * 1e18
    );

    // Setup users
    _setupUsers();

    // Labels
    vm.label(address(ldyToken), "LDY Token");
    vm.label(address(legacyStaking), "LegacyStakingTransition");
    vm.label(testAccount1, "Alice");
    vm.label(testAccount2, "Bob");
  }

  function _setupUsers() internal {
    deal(address(ldyToken), testAccount1, INITIAL_BALANCE);
    deal(address(ldyToken), testAccount2, INITIAL_BALANCE);
    deal(address(ldyToken), owner, INITIAL_BALANCE);

    vm.prank(testAccount1);
    ldyToken.approve(address(legacyStaking), type(uint256).max);

    vm.prank(testAccount2);
    ldyToken.approve(address(legacyStaking), type(uint256).max);

    vm.prank(owner);
    ldyToken.approve(address(legacyStaking), type(uint256).max);
  }

  /*//////////////////////////////////////////////////////////////
                    EARLY WITHDRAWALS TESTS
  //////////////////////////////////////////////////////////////*/

  function test_SetEarlyWithdrawalsEnabled_Success() public {
    assertFalse(legacyStaking.earlyWithdrawalsEnabled());

    vm.expectEmit(address(legacyStaking));
    emit EarlyWithdrawalsToggled(true);

    legacyStaking.setEarlyWithdrawalsEnabled(true);

    assertTrue(legacyStaking.earlyWithdrawalsEnabled());
  }

  function test_SetEarlyWithdrawalsEnabled_Toggle() public {
    legacyStaking.setEarlyWithdrawalsEnabled(true);
    assertTrue(legacyStaking.earlyWithdrawalsEnabled());

    legacyStaking.setEarlyWithdrawalsEnabled(false);
    assertFalse(legacyStaking.earlyWithdrawalsEnabled());
  }

  function test_SetEarlyWithdrawalsEnabled_OnlyOwner() public {
    vm.prank(testAccount1);
    vm.expectRevert();
    legacyStaking.setEarlyWithdrawalsEnabled(true);
  }

  function test_EarlyWithdrawal_FailsWhenDisabled() public {
    // Stake with 1 year lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 2); // 365 days lock

    // Try to unstake immediately - should fail
    vm.prank(testAccount1);
    vm.expectRevert("Cannot unstake during staking period");
    legacyStaking.unstake(TEST_AMOUNT, 0);
  }

  function test_EarlyWithdrawal_SucceedsWhenEnabled() public {
    // Stake with 1 year lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 2); // 365 days lock

    // Enable early withdrawals
    legacyStaking.setEarlyWithdrawalsEnabled(true);

    uint256 balanceBefore = ldyToken.balanceOf(testAccount1);

    // Unstake immediately - should succeed
    vm.prank(testAccount1);
    vm.expectEmit(address(legacyStaking));
    emit Unstaked(testAccount1, 0, TEST_AMOUNT);
    legacyStaking.unstake(TEST_AMOUNT, 0);

    assertEq(
      ldyToken.balanceOf(testAccount1),
      balanceBefore + TEST_AMOUNT
    );
  }

  function test_EarlyWithdrawal_PartialUnstake() public {
    // Stake with 1 year lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 2); // 365 days lock

    // Enable early withdrawals
    legacyStaking.setEarlyWithdrawalsEnabled(true);

    uint256 partialAmount = TEST_AMOUNT / 2;
    uint256 balanceBefore = ldyToken.balanceOf(testAccount1);

    // Partial unstake
    vm.prank(testAccount1);
    legacyStaking.unstake(partialAmount, 0);

    assertEq(
      ldyToken.balanceOf(testAccount1),
      balanceBefore + partialAmount
    );

    // Check remaining stake
    (uint256 stakedAmount, , , , ) = legacyStaking.userStakingInfo(
      testAccount1,
      0
    );
    assertEq(stakedAmount, TEST_AMOUNT - partialAmount);
  }

  function test_NormalWithdrawal_StillWorksAfterLockExpiry() public {
    // Stake with 30 day lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 1); // 30 days lock

    // Fast forward past lock
    vm.warp(block.timestamp + 31 days);

    uint256 balanceBefore = ldyToken.balanceOf(testAccount1);

    // Should be able to unstake without early withdrawals enabled
    vm.prank(testAccount1);
    legacyStaking.unstake(TEST_AMOUNT, 0);

    assertEq(
      ldyToken.balanceOf(testAccount1),
      balanceBefore + TEST_AMOUNT
    );
  }

  /*//////////////////////////////////////////////////////////////
                    WITHDRAW UNDISTRIBUTED REWARDS TESTS
  //////////////////////////////////////////////////////////////*/

  function test_WithdrawUndistributedRewards_Success() public {
    // Setup rewards duration and notify rewards
    legacyStaking.setRewardsDuration(30 days);

    // Stake some tokens first
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 0);

    // Notify reward amount
    legacyStaking.notifyRewardAmount(REWARD_AMOUNT);

    // Fast forward halfway through rewards period
    vm.warp(block.timestamp + 15 days);

    // Calculate expected undistributed (roughly half)
    uint256 ownerBalanceBefore = ldyToken.balanceOf(owner);

    vm.expectEmit(false, false, false, false, address(legacyStaking));
    emit UndistributedRewardsWithdrawn(0); // Amount checked separately

    legacyStaking.withdrawUndistributedRewards();

    uint256 ownerBalanceAfter = ldyToken.balanceOf(owner);
    uint256 withdrawn = ownerBalanceAfter - ownerBalanceBefore;

    // Should have withdrawn approximately half the rewards
    assertGt(withdrawn, 0);
    assertApproxEqRel(withdrawn, REWARD_AMOUNT / 2, 0.1e18);

    // Reward rate should be reset
    assertEq(legacyStaking.rewardRatePerSec(), 0);
    assertEq(legacyStaking.finishAt(), block.timestamp);
  }

  function test_WithdrawUndistributedRewards_AfterPeriodEnds()
    public
  {
    // Setup rewards duration and notify rewards
    legacyStaking.setRewardsDuration(30 days);

    // Stake some tokens first
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 0);

    // Notify reward amount
    legacyStaking.notifyRewardAmount(REWARD_AMOUNT);

    // Fast forward past rewards period
    vm.warp(block.timestamp + 31 days);

    // All rewards should be distributed, nothing to withdraw
    vm.expectRevert("No undistributed rewards");
    legacyStaking.withdrawUndistributedRewards();
  }

  function test_WithdrawUndistributedRewards_OnlyOwner() public {
    vm.prank(testAccount1);
    vm.expectRevert();
    legacyStaking.withdrawUndistributedRewards();
  }

  function test_WithdrawUndistributedRewards_NoRewardsToWithdraw()
    public
  {
    // No rewards deposited
    vm.expectRevert("No undistributed rewards");
    legacyStaking.withdrawUndistributedRewards();
  }

  function test_WithdrawUndistributedRewards_PreservesUserRewards()
    public
  {
    // Setup rewards duration and notify rewards
    legacyStaking.setRewardsDuration(30 days);

    // Stake some tokens
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 0);

    // Notify reward amount
    legacyStaking.notifyRewardAmount(REWARD_AMOUNT);

    // Fast forward 15 days
    vm.warp(block.timestamp + 15 days);

    // Check user's earned rewards before withdrawal
    uint256 earnedBefore = legacyStaking.earned(testAccount1, 0);
    assertGt(earnedBefore, 0);

    // Withdraw undistributed rewards
    legacyStaking.withdrawUndistributedRewards();

    // User should still be able to claim their earned rewards
    uint256 earnedAfter = legacyStaking.earned(testAccount1, 0);
    assertEq(earnedAfter, earnedBefore);

    // User claims rewards
    uint256 balanceBefore = ldyToken.balanceOf(testAccount1);
    vm.prank(testAccount1);
    legacyStaking.getReward(0);

    assertEq(
      ldyToken.balanceOf(testAccount1),
      balanceBefore + earnedBefore
    );
  }

  /*//////////////////////////////////////////////////////////////
                    STORAGE LAYOUT SAFETY TESTS
  //////////////////////////////////////////////////////////////*/

  function test_StorageLayout_EarlyWithdrawalsDefaultsFalse()
    public
    view
  {
    assertFalse(legacyStaking.earlyWithdrawalsEnabled());
  }

  function test_StorageLayout_ExistingStorageUnaffected() public {
    // Stake tokens
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 1);

    // Verify existing storage works correctly
    assertEq(legacyStaking.totalStaked(), TEST_AMOUNT);
    assertEq(
      address(legacyStaking.stakeRewardToken()),
      address(ldyToken)
    );

    // Toggle early withdrawals
    legacyStaking.setEarlyWithdrawalsEnabled(true);

    // Verify existing storage still works
    assertEq(legacyStaking.totalStaked(), TEST_AMOUNT);
    assertEq(
      address(legacyStaking.stakeRewardToken()),
      address(ldyToken)
    );

    (
      uint256 stakedAmount,
      uint256 unStakeAt,
      uint256 duration,
      ,

    ) = legacyStaking.userStakingInfo(testAccount1, 0);
    assertEq(stakedAmount, TEST_AMOUNT);
    assertEq(duration, 30 days);
    assertGt(unStakeAt, block.timestamp);
  }

  /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
  //////////////////////////////////////////////////////////////*/

  function test_Integration_EarlyWithdrawalWithRewards() public {
    // Setup rewards
    legacyStaking.setRewardsDuration(30 days);

    // Stake with lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 2); // 365 days lock

    // Notify rewards
    legacyStaking.notifyRewardAmount(REWARD_AMOUNT);

    // Fast forward 15 days
    vm.warp(block.timestamp + 15 days);

    // Check earned rewards
    uint256 earned = legacyStaking.earned(testAccount1, 0);
    assertGt(earned, 0);

    // Enable early withdrawals
    legacyStaking.setEarlyWithdrawalsEnabled(true);

    // Unstake fully (should also claim rewards)
    uint256 balanceBefore = ldyToken.balanceOf(testAccount1);
    vm.prank(testAccount1);
    legacyStaking.unstake(TEST_AMOUNT, 0);

    // Should receive stake + rewards
    assertEq(
      ldyToken.balanceOf(testAccount1),
      balanceBefore + TEST_AMOUNT + earned
    );
  }

  function test_Integration_MultipleUsersEarlyWithdrawal() public {
    // Both users stake with lock
    vm.prank(testAccount1);
    legacyStaking.stake(TEST_AMOUNT, 2); // 365 days lock

    vm.prank(testAccount2);
    legacyStaking.stake(TEST_AMOUNT * 2, 2); // 365 days lock

    assertEq(legacyStaking.totalStaked(), TEST_AMOUNT * 3);

    // Enable early withdrawals
    legacyStaking.setEarlyWithdrawalsEnabled(true);

    // Both users can withdraw
    vm.prank(testAccount1);
    legacyStaking.unstake(TEST_AMOUNT, 0);

    vm.prank(testAccount2);
    legacyStaking.unstake(TEST_AMOUNT * 2, 0);

    assertEq(legacyStaking.totalStaked(), 0);
  }
}
