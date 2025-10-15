// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract StakingPositions_UnitTest is Test, Fixtures {
  event Approval(
    address indexed owner,
    address indexed approved,
    uint256 indexed tokenId
  );
  event ApprovalForAll(
    address indexed owner,
    address indexed operator,
    bool approved
  );

  uint256 public constant WEEK = 7 * 86400;
  uint256 public constant TEST_AMOUNT = 1000 * 1e18;
  uint256 public constant TEST_LOCK_DURATION = 52 * WEEK; // 1 year

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 indexed tokenId
  );
  event Deposit(
    address indexed provider,
    uint256 indexed tokenId,
    IStakingPositions.DepositType indexed depositType,
    uint256 value,
    uint256 locktime,
    uint256 ts
  );
  event Withdraw(
    address indexed provider,
    uint256 indexed tokenId,
    uint256 value,
    uint256 ts
  );
  event Supply(uint256 prevSupply, uint256 supply);

  function setUp() public {
    _setUp();
    _setupUsers();
  }

  function _setupUsers() internal {
    // Mint tokens to test users
    for (uint256 i = 0; i < users.length; i++) {
      deal(address(ldyToken), users[i], INITIAL_BALANCE);

      vm.prank(users[i]);
      ldyToken.approve(address(stakingPositions), type(uint256).max);
    }
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Initialize() public view {
    assertEq(stakingPositions.token(), address(ldyToken));
    assertEq(stakingPositions.name(), "Ledgity Staking Positions");
    assertEq(stakingPositions.symbol(), "lsNFT");
    assertEq(stakingPositions.decimals(), 18);
    assertEq(stakingPositions.maxTime(), MAX_STAKE_TIME);
    assertEq(stakingPositions.tokenId(), 0);
    assertEq(stakingPositions.epoch(), 0);
    assertEq(stakingPositions.supply(), 0);
  }

  function test_SupportsInterface() public view {
    // ERC165
    assertTrue(stakingPositions.supportsInterface(0x01ffc9a7));
    // ERC721
    assertTrue(stakingPositions.supportsInterface(0x80ac58cd));
    // ERC721Metadata
    assertTrue(stakingPositions.supportsInterface(0x5b5e139f));
    // ERC4906
    assertTrue(stakingPositions.supportsInterface(0x49064906));
    // ERC6372
    assertTrue(stakingPositions.supportsInterface(0xda287a1d));
  }

  /*//////////////////////////////////////////////////////////////
                            CREATE LOCK TESTS
    //////////////////////////////////////////////////////////////*/

  function test_CreateLock_Success() public {
    uint256 amount = TEST_AMOUNT;
    uint256 lockDuration = TEST_LOCK_DURATION;

    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Transfer(address(0), testAccount1, 1);

    vm.expectEmit(true, true, true, true);
    emit Deposit(
      testAccount1,
      1,
      IStakingPositions.DepositType.CREATE_LOCK_TYPE,
      amount,
      ((block.timestamp + lockDuration) / WEEK) * WEEK,
      block.timestamp
    );

    vm.expectEmit(true, true, true, true);
    emit Supply(0, amount);

    uint256 tokenId = stakingPositions.createLock(
      amount,
      lockDuration
    );

    vm.stopPrank();

    assertEq(tokenId, 1);
    assertEq(stakingPositions.ownerOf(tokenId), testAccount1);
    assertEq(stakingPositions.balanceOf(testAccount1), 1);
    assertEq(stakingPositions.supply(), amount);

    IStakingPositions.LockedBalance memory locked = stakingPositions
      .getLockedBalance(tokenId);
    assertEq(uint256(uint128(locked.amount)), amount);
    assertEq(
      locked.end,
      ((block.timestamp + lockDuration) / WEEK) * WEEK
    );

    // Check voting power is greater than 0
    assertGt(stakingPositions.balanceOfNFT(tokenId), 0);
  }

  function test_CreateLock_RevertZeroAmount() public {
    vm.startPrank(testAccount1);

    vm.expectRevert(IStakingPositions.ZeroAmount.selector);
    stakingPositions.createLock(0, TEST_LOCK_DURATION);

    vm.stopPrank();
  }

  function test_CreateLock_RevertLockDurationNotInFuture() public {
    vm.startPrank(testAccount1);

    vm.expectRevert(
      IStakingPositions.LockDurationNotInFuture.selector
    );
    stakingPositions.createLock(TEST_AMOUNT, 0);

    vm.stopPrank();
  }

  function test_CreateLock_RevertLockDurationTooLong() public {
    vm.startPrank(testAccount1);

    vm.expectRevert(IStakingPositions.LockDurationTooLong.selector);
    // Since it is rounded down we need to add a week in excess
    stakingPositions.createLock(
      TEST_AMOUNT,
      MAX_STAKE_TIME + WEEK + 1
    );

    vm.stopPrank();
  }

  function test_CreateLock_MultipleTokens() public {
    vm.startPrank(testAccount1);

    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION / 2
    );

    vm.stopPrank();

    assertEq(tokenId1, 1);
    assertEq(tokenId2, 2);
    assertEq(stakingPositions.balanceOf(testAccount1), 2);
    assertEq(stakingPositions.supply(), TEST_AMOUNT * 2);
  }

  /*//////////////////////////////////////////////////////////////
                            INCREASE AMOUNT TESTS
    //////////////////////////////////////////////////////////////*/

  function test_IncreaseAmount_Success() public {
    // Create initial lock
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    uint256 additionalAmount = TEST_AMOUNT / 2;

    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Deposit(
      testAccount1,
      tokenId,
      IStakingPositions.DepositType.INCREASE_LOCK_AMOUNT,
      additionalAmount,
      ((block.timestamp + TEST_LOCK_DURATION) / WEEK) * WEEK,
      block.timestamp
    );

    stakingPositions.increaseAmount(tokenId, additionalAmount);

    vm.stopPrank();

    IStakingPositions.LockedBalance memory locked = stakingPositions
      .getLockedBalance(tokenId);
    assertEq(
      uint256(uint128(locked.amount)),
      TEST_AMOUNT + additionalAmount
    );
    assertEq(
      stakingPositions.supply(),
      TEST_AMOUNT + additionalAmount
    );
  }

  function test_IncreaseAmount_RevertNotApprovedOrOwner() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount2);

    vm.expectRevert(IStakingPositions.NotApprovedOrOwner.selector);
    stakingPositions.increaseAmount(tokenId, TEST_AMOUNT);

    vm.stopPrank();
  }

  function test_IncreaseAmount_RevertZeroAmount() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount1);

    vm.expectRevert(IStakingPositions.ZeroAmount.selector);
    stakingPositions.increaseAmount(tokenId, 0);

    vm.stopPrank();
  }

  function test_IncreaseAmount_RevertLockExpired() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, WEEK);

    // Fast forward past lock expiry
    vm.warp(block.timestamp + WEEK + 1);

    vm.startPrank(testAccount1);

    vm.expectRevert(IStakingPositions.LockExpired.selector);
    stakingPositions.increaseAmount(tokenId, TEST_AMOUNT);

    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////
                            INCREASE UNLOCK TIME TESTS
    //////////////////////////////////////////////////////////////*/

  function test_IncreaseUnlockTime_Success() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    uint256 additionalDuration = 26 * WEEK; // 6 months

    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Deposit(
      testAccount1,
      tokenId,
      IStakingPositions.DepositType.INCREASE_UNLOCK_TIME,
      0, // no additional amount
      ((block.timestamp + TEST_LOCK_DURATION + additionalDuration) /
        WEEK) * WEEK,
      block.timestamp
    );

    stakingPositions.increaseUnlockTime(
      tokenId,
      TEST_LOCK_DURATION + additionalDuration
    );

    vm.stopPrank();

    IStakingPositions.LockedBalance memory locked = stakingPositions
      .getLockedBalance(tokenId);
    assertEq(
      locked.end,
      ((block.timestamp + TEST_LOCK_DURATION + additionalDuration) /
        WEEK) * WEEK
    );
  }

  function test_IncreaseUnlockTime_RevertLockDurationNotInFuture()
    public
  {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount1);

    vm.expectRevert(
      IStakingPositions.LockDurationNotInFuture.selector
    );
    stakingPositions.increaseUnlockTime(
      tokenId,
      TEST_LOCK_DURATION - WEEK
    );

    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////
                            WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Withdraw_Success() public {
    uint256 initialBalance = ldyToken.balanceOf(testAccount1);

    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, WEEK);

    // Fast forward past lock expiry
    vm.warp(block.timestamp + WEEK + 1);

    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Transfer(testAccount1, address(0), tokenId);

    vm.expectEmit(true, true, true, true);
    emit Withdraw(
      testAccount1,
      tokenId,
      TEST_AMOUNT,
      block.timestamp
    );

    vm.expectEmit(true, true, true, true);
    emit Supply(TEST_AMOUNT, 0);

    stakingPositions.withdraw(tokenId);

    vm.stopPrank();

    // Check NFT is burned
    address owner = stakingPositions.ownerOf(tokenId);
    assertEq(owner, address(0));

    assertEq(stakingPositions.balanceOf(testAccount1), 0);
    assertEq(stakingPositions.supply(), 0);
    assertEq(ldyToken.balanceOf(testAccount1), initialBalance);
  }

  function test_Withdraw_RevertLockNotExpired() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount1);

    vm.expectRevert(IStakingPositions.LockNotExpired.selector);
    stakingPositions.withdraw(tokenId);

    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////
                            DEPOSIT FOR TESTS
    //////////////////////////////////////////////////////////////*/

  function test_DepositFor_Success() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    uint256 depositAmount = TEST_AMOUNT / 2;

    vm.startPrank(testAccount2);

    vm.expectEmit(true, true, true, true);
    emit Deposit(
      testAccount2,
      tokenId,
      IStakingPositions.DepositType.DEPOSIT_FOR_TYPE,
      depositAmount,
      ((block.timestamp + TEST_LOCK_DURATION) / WEEK) * WEEK,
      block.timestamp
    );

    stakingPositions.depositFor(tokenId, depositAmount);

    vm.stopPrank();

    IStakingPositions.LockedBalance memory locked = stakingPositions
      .getLockedBalance(tokenId);
    assertEq(
      uint256(uint128(locked.amount)),
      TEST_AMOUNT + depositAmount
    );
    assertEq(stakingPositions.supply(), TEST_AMOUNT + depositAmount);

    // Owner should still be testAccount1
    assertEq(stakingPositions.ownerOf(tokenId), testAccount1);
  }

  /*//////////////////////////////////////////////////////////////
                            ERC721 FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Approve_Success() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Approval(testAccount1, testAccount2, tokenId);

    stakingPositions.approve(testAccount2, tokenId);

    vm.stopPrank();

    assertEq(stakingPositions.getApproved(tokenId), testAccount2);
    assertTrue(
      stakingPositions.isApprovedOrOwner(testAccount2, tokenId)
    );
  }

  function test_SetApprovalForAll_Success() public {
    vm.startPrank(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit ApprovalForAll(testAccount1, testAccount2, true);

    stakingPositions.setApprovalForAll(testAccount2, true);

    vm.stopPrank();

    assertTrue(
      stakingPositions.isApprovedForAll(testAccount1, testAccount2)
    );
  }

  function test_TransferFrom_Success() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    vm.prank(testAccount1);
    stakingPositions.approve(testAccount2, tokenId);

    vm.startPrank(testAccount2);

    vm.expectEmit(true, true, true, true);
    emit Transfer(testAccount1, testAccount3, tokenId);

    stakingPositions.transferFrom(
      testAccount1,
      testAccount3,
      tokenId
    );

    vm.stopPrank();

    assertEq(stakingPositions.ownerOf(tokenId), testAccount3);
    assertEq(stakingPositions.balanceOf(testAccount1), 0);
    assertEq(stakingPositions.balanceOf(testAccount3), 1);
    assertEq(stakingPositions.getApproved(tokenId), address(0)); // Approval cleared
  }

  /*//////////////////////////////////////////////////////////////
                            VOTING POWER TESTS
    //////////////////////////////////////////////////////////////*/

  function test_VotingPower_DecaysOverTime() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    uint256 initialVotingPower = stakingPositions.balanceOfNFT(
      tokenId
    );
    assertGt(initialVotingPower, 0);

    // Fast forward halfway through lock period
    vm.warp(block.timestamp + TEST_LOCK_DURATION / 2);

    uint256 halfwayVotingPower = stakingPositions.balanceOfNFT(
      tokenId
    );
    assertLt(halfwayVotingPower, initialVotingPower);
    assertGt(halfwayVotingPower, 0);

    // Fast forward to just before expiry
    vm.warp(block.timestamp + TEST_LOCK_DURATION / 2 - 1);

    uint256 nearExpiryVotingPower = stakingPositions.balanceOfNFT(
      tokenId
    );
    assertLt(nearExpiryVotingPower, halfwayVotingPower);
  }

  function test_VotingPower_ZeroAfterExpiry() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(TEST_AMOUNT, WEEK);

    // Fast forward past expiry
    vm.warp(block.timestamp + WEEK + 1);

    uint256 expiredVotingPower = stakingPositions.balanceOfNFT(
      tokenId
    );
    assertEq(expiredVotingPower, 0);
  }

  function test_TotalSupply_UpdatesCorrectly() public {
    assertEq(stakingPositions.totalSupply(), 0);

    vm.prank(testAccount1);
    stakingPositions.createLock(TEST_AMOUNT, TEST_LOCK_DURATION);

    uint256 totalSupplyAfterFirst = stakingPositions.totalSupply();
    assertGt(totalSupplyAfterFirst, 0);

    vm.prank(testAccount2);
    stakingPositions.createLock(TEST_AMOUNT, TEST_LOCK_DURATION);

    uint256 totalSupplyAfterSecond = stakingPositions.totalSupply();
    assertGt(totalSupplyAfterSecond, totalSupplyAfterFirst);
  }

  function test_GetUserNFTs() public {
    vm.startPrank(testAccount1);

    uint256 tokenId1 = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );
    uint256 tokenId2 = stakingPositions.createLock(
      TEST_AMOUNT / 2,
      TEST_LOCK_DURATION / 2
    );

    vm.stopPrank();

    IStakingPositions.NFTData[] memory nfts = stakingPositions
      .getUserNFTs(testAccount1);

    assertEq(nfts.length, 2);
    assertEq(nfts[0].tokenId, tokenId1);
    assertEq(nfts[1].tokenId, tokenId2);
    assertEq(nfts[0].owner, testAccount1);
    assertEq(nfts[1].owner, testAccount1);
    assertGt(nfts[0].votingPower, 0);
    assertGt(nfts[1].votingPower, 0);
  }

  function test_GetUserTotalVotingPower() public {
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

    uint256 totalVotingPower = stakingPositions
      .getUserTotalVotingPower(testAccount1);
    uint256 token1Power = stakingPositions.balanceOfNFT(tokenId1);
    uint256 token2Power = stakingPositions.balanceOfNFT(tokenId2);

    assertEq(totalVotingPower, token1Power + token2Power);
  }

  /*//////////////////////////////////////////////////////////////
                            CHECKPOINT TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Checkpoint_Success() public {
    stakingPositions.checkpoint();

    // Should not revert and should update epoch
    assertGt(stakingPositions.epoch(), 0);
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

  function test_SetMaxTime_Success() public {
    uint256 newMaxTime = 2 * 365 * 86400; // 2 years

    vm.prank(address(globalOwner.owner()));
    stakingPositions.setMaxTime(newMaxTime);

    assertEq(stakingPositions.maxTime(), newMaxTime);
    assertEq(
      stakingPositions.iMaxTime(),
      int128(uint128(newMaxTime))
    );
  }

  function test_SetMaxTime_RevertNotOwner() public {
    vm.startPrank(testAccount1);

    vm.expectRevert();
    stakingPositions.setMaxTime(365 * 86400);

    vm.stopPrank();
  }

  function test_SetArtProxy_Success() public {
    address newArtProxy = address(0x123);

    vm.prank(globalOwner.owner());
    stakingPositions.setArtProxy(newArtProxy);

    assertEq(stakingPositions.artProxy(), newArtProxy);
  }

  function test_SetArtProxy_RevertNotOwner() public {
    vm.startPrank(testAccount1);

    vm.expectRevert();
    stakingPositions.setArtProxy(address(0x123));

    vm.stopPrank();
  }

  /*//////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

  function test_BalanceOfNFT_ZeroInSameBlock() public {
    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      TEST_LOCK_DURATION
    );

    // Transfer in same block
    vm.prank(testAccount1);
    stakingPositions.transferFrom(
      testAccount1,
      testAccount2,
      tokenId
    );

    // Should return 0 in same block as transfer
    assertEq(stakingPositions.balanceOfNFT(tokenId), 0);

    // Move to next block
    vm.roll(block.number + 1);

    // Should return actual voting power
    assertGt(stakingPositions.balanceOfNFT(tokenId), 0);
  }

  function test_LockDuration_RoundedToWeeks() public {
    uint256 irregularDuration = TEST_LOCK_DURATION + 3 * 86400; // Add 3 days

    vm.prank(testAccount1);
    uint256 tokenId = stakingPositions.createLock(
      TEST_AMOUNT,
      irregularDuration
    );

    IStakingPositions.LockedBalance memory locked = stakingPositions
      .getLockedBalance(tokenId);

    // Should be rounded down to nearest week
    uint256 expectedEnd = ((block.timestamp + irregularDuration) /
      WEEK) * WEEK;
    assertEq(locked.end, expectedEnd);
  }
}

// Helper contract for testing ERC721Receiver functionality
contract MockERC721Receiver is IERC721Receiver {
  bool public shouldReject;

  function setShouldReject(bool _shouldReject) external {
    shouldReject = _shouldReject;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external view override returns (bytes4) {
    if (shouldReject) {
      revert("Receiver rejected");
    }
    return IERC721Receiver.onERC721Received.selector;
  }
}
