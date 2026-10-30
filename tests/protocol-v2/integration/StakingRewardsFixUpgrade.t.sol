// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
import { StakingPositionsSonic } from "src/protocol-v2/chainSonic/StakingPositionsSonic.sol";
import { StakingRewardsDistributorSonic } from "src/protocol-v2/chainSonic/StakingRewardsDistributor.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";

/**
 * @title Skip_StakingRewardsFixUpgradeFork
 * @notice Rehearses the upgrade of the live StakingPositions and StakingRewardsDistributor
 * proxies to the implementations fixing the base reward cursors and the maxTime slope, on a
 * fork of the target chain:
 *   - every position and distributor value read before the upgrade reads the same after it,
 *   - protocol rewards claimable are unchanged, base rewards claimable never decrease,
 *   - a full lifecycle (every position claims to the end of the reward periods, expired
 *     locks withdraw) never pays more than the distributor holds and pays no week twice.
 *
 * @dev Skipped by the default suites (Skip_ prefix). Run one chain at a time with
 * `npm run test:upgrade-staking:<chain>`, which sets HARDHAT_DEPLOY_FORK and expects
 * <CHAIN>_RPC_URL (and optionally <CHAIN>_FORKING_BLOCK) in the environment.
 */
contract Skip_StakingRewardsFixUpgradeFork is Test {
  uint256 constant WEEK = 1 weeks;

  struct PositionSnapshot {
    address owner;
    int128 amount;
    uint256 end;
    uint256 userPointEpoch;
    uint256 votingPower;
    uint256 baseRewardCursor;
    uint256 protocolRewardCursor;
    uint256 protocolRewardsPerTokenPaid;
    uint256 accruedProtocolRewards;
    uint256 claimableBase;
    uint256 claimableProtocol;
  }

  StakingPositions staking;
  StakingRewardsDistributor distributor;
  IERC20 ldy;
  address safe;
  bool isSonic;
  bool isBase;

  address newStakingImpl;
  address newDistributorImpl;

  function setUp() public {
    string memory fork = vm.envOr(
      "HARDHAT_DEPLOY_FORK",
      string("base")
    );
    address stakingProxy;

    if (_eq(fork, "mainnet")) {
      _fork("MAINNET");
      stakingProxy = 0xEB4B058BF032E1eD61AA1fEcA332a8b8b96F7483;
    } else if (_eq(fork, "base")) {
      _fork("BASE");
      stakingProxy = 0x0fCfdF9B6572116FA662A5CF8a074B51EB2D6d88;
      isBase = true;
    } else if (_eq(fork, "arbitrum")) {
      _fork("ARBITRUM");
      stakingProxy = 0x6E83612c73f124127d49eA642c392FF4d9eAFd5b;
    } else if (_eq(fork, "sonic")) {
      _fork("SONIC");
      stakingProxy = 0x613904B9a1Af4450FD34655d123EEb0944888b21;
      isSonic = true;
    } else {
      revert(string.concat("Unsupported fork target: ", fork));
    }

    staking = StakingPositions(stakingProxy);
    distributor = StakingRewardsDistributor(
      staking.rewardsDistributor()
    );
    ldy = IERC20(staking.token());
    safe = staking.owner();

    newStakingImpl = isSonic
      ? address(new StakingPositionsSonic())
      : address(new StakingPositions());
    newDistributorImpl = isSonic
      ? address(new StakingRewardsDistributorSonic())
      : address(new StakingRewardsDistributor());
  }

  // ======== HELPERS ======== //

  function _eq(
    string memory a,
    string memory b
  ) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  /// @dev Same <CHAIN>_RPC_URL / <CHAIN>_FORKING_BLOCK convention as the v2 fixtures
  function _fork(string memory prefix) internal {
    string memory rpcUrl = vm.envString(
      string.concat(prefix, "_RPC_URL")
    );
    string memory blockStr = vm.envOr(
      string.concat(prefix, "_FORKING_BLOCK"),
      string("")
    );
    if (bytes(blockStr).length > 0 && !_eq(blockStr, "latest")) {
      vm.createSelectFork(rpcUrl, vm.parseUint(blockStr));
    } else {
      vm.createSelectFork(rpcUrl);
    }
  }

  function _snapshot(
    uint256 tokenId
  ) internal view returns (PositionSnapshot memory s) {
    IStakingPositions.LockedBalance memory locked = staking
      .getLockedBalance(tokenId);
    s.owner = staking.ownerOf(tokenId);
    s.amount = locked.amount;
    s.end = locked.end;
    s.userPointEpoch = staking.userPointEpoch(tokenId);
    s.votingPower = staking.balanceOfNFTAt(tokenId, block.timestamp);
    s.baseRewardCursor = distributor.baseRewardCursor(tokenId);
    s.protocolRewardCursor = distributor.protocolRewardCursor(
      tokenId
    );
    s.protocolRewardsPerTokenPaid = distributor
      .protocolRewardsPerTokenPaid(tokenId);
    s.accruedProtocolRewards = distributor.accruedProtocolRewards(
      tokenId
    );
    (s.claimableBase, s.claimableProtocol) = distributor.claimable(
      tokenId
    );
  }

  function _upgrade() internal {
    vm.startPrank(safe);
    UUPSUpgradeable(address(staking)).upgradeTo(newStakingImpl);
    UUPSUpgradeable(address(distributor)).upgradeTo(
      newDistributorImpl
    );
    vm.stopPrank();
  }

  /// @dev Claims until the token's week cursor reaches the current week
  function _claimAll(
    uint256 tokenId
  ) internal returns (uint256 paid) {
    address owner = staking.ownerOf(tokenId);
    if (owner == address(0)) return 0;
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    for (uint256 i; i < 10; i++) {
      vm.prank(owner);
      (uint256 base, uint256 protocol) = distributor.claim(tokenId);
      paid += base + protocol;
      if (distributor.baseRewardCursor(tokenId) >= currentWeek) break;
    }
  }

  // ======== TESTS ======== //

  function test_upgrade_preservesState() public {
    uint256 lastId = staking.tokenId();
    PositionSnapshot[] memory before = new PositionSnapshot[](
      lastId + 1
    );
    for (uint256 id = 1; id <= lastId; id++)
      before[id] = _snapshot(id);

    uint256 epoch = staking.epoch();
    uint256 supply = staking.supply();
    uint256 totalVotingPower = staking.totalSupply();
    uint256 maxTime = staking.maxTime();
    uint256 currentPeriodId = distributor.currentPeriodId();
    uint256 cumulative = distributor
      .cumulativeProtocolRewardsPerToken();
    uint256 startTime = distributor.startTime();
    uint256 distributorBalance = ldy.balanceOf(address(distributor));

    _upgrade();

    assertEq(staking.epoch(), epoch, "epoch");
    assertEq(staking.supply(), supply, "supply");
    assertEq(
      staking.totalSupply(),
      totalVotingPower,
      "total voting power"
    );
    assertEq(staking.maxTime(), maxTime, "maxTime");
    assertEq(staking.rewardsDistributor(), address(distributor));
    assertEq(address(distributor.staking()), address(staking));
    assertEq(distributor.token(), address(ldy));
    assertEq(
      distributor.currentPeriodId(),
      currentPeriodId,
      "periods"
    );
    assertEq(
      distributor.cumulativeProtocolRewardsPerToken(),
      cumulative
    );
    assertEq(distributor.startTime(), startTime, "startTime");
    // Appended slot, never written by the deployed implementation
    assertEq(
      distributor.pendingProtocolFees(),
      0,
      "pendingProtocolFees"
    );
    assertEq(ldy.balanceOf(address(distributor)), distributorBalance);

    for (uint256 id = 1; id <= lastId; id++) {
      PositionSnapshot memory b = before[id];
      PositionSnapshot memory a = _snapshot(id);
      assertEq(a.owner, b.owner, "owner");
      assertEq(a.amount, b.amount, "locked amount");
      assertEq(a.end, b.end, "lock end");
      assertEq(a.userPointEpoch, b.userPointEpoch, "user epoch");
      assertEq(a.votingPower, b.votingPower, "voting power");
      assertEq(a.baseRewardCursor, b.baseRewardCursor, "week cursor");
      assertEq(a.protocolRewardCursor, b.protocolRewardCursor);
      assertEq(
        a.protocolRewardsPerTokenPaid,
        b.protocolRewardsPerTokenPaid
      );
      assertEq(a.accruedProtocolRewards, b.accruedProtocolRewards);
      assertEq(
        a.claimableProtocol,
        b.claimableProtocol,
        "protocol claimable"
      );
      // Base claimable can only grow: positions that skipped a running period get it back
      assertGe(
        a.claimableBase,
        b.claimableBase,
        "base claimable decreased"
      );
      if (!isBase)
        assertEq(a.claimableBase, b.claimableBase, "base claimable");
    }
  }

  function test_upgrade_noDoubleClaimAndDistributorStaysSolvent()
    public
  {
    _upgrade();
    uint256 lastId = staking.tokenId();
    uint256 available = ldy.balanceOf(address(distributor));

    // Past the end of every running period, with positions more than 50 weeks behind
    uint256 lastEnd;
    for (uint256 p = 1; p <= distributor.currentPeriodId(); p++) {
      (, uint256 endWeek, , ) = distributor.baseRewardPeriods(p);
      if (endWeek > lastEnd) lastEnd = endWeek;
    }
    vm.warp(
      (lastEnd > block.timestamp ? lastEnd : block.timestamp) +
        2 *
        WEEK
    );

    uint256 paid;
    for (uint256 id = 1; id <= lastId; id++) {
      paid += _claimAll(id);
      // A second pass the same week must pay nothing
      address owner = staking.ownerOf(id);
      if (owner == address(0)) continue;
      vm.prank(owner);
      (uint256 base, uint256 protocol) = distributor.claim(id);
      assertEq(base + protocol, 0, "paid twice");
    }

    assertLe(paid, available, "paid more than the distributor held");
    assertEq(
      ldy.balanceOf(address(distributor)),
      available - paid,
      "distributor balance"
    );

    // Expired locks can still withdraw their principal
    for (uint256 id = 1; id <= lastId; id++) {
      address owner = staking.ownerOf(id);
      IStakingPositions.LockedBalance memory locked = staking
        .getLockedBalance(id);
      if (owner == address(0) || block.timestamp < locked.end)
        continue;
      uint256 before = ldy.balanceOf(owner);
      vm.prank(owner);
      staking.withdraw(id);
      assertEq(
        ldy.balanceOf(owner) - before,
        uint256(int256(locked.amount)),
        "principal"
      );
    }
  }
}
