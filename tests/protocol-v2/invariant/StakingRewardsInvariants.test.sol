// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";
import { StdInvariant } from "foundry/lib/forge-std/src/StdInvariant.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GlobalOwner } from "src/protocol-v1/GlobalOwner.sol";
import { GlobalPause } from "src/protocol-v1/GlobalPause.sol";
import { GenericERC20 } from "src/protocol-v1/GenericERC20.sol";
import { GlobalAccessList } from "src/protocol-v2/GlobalAccessList.sol";
import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";

/**
 * @dev Drives random sequences of every staking and reward action and checks each claim
 *      against an independent model (no cursor, no window logic): the exact amount, and a
 *      claimed window that starts where the previous one ended (no week twice, none skipped).
 */
contract StakingRewardsHandler is Test {
  uint256 constant WEEK = 1 weeks;
  uint256 constant MAX_TOKENS = 12;

  StakingPositions public staking;
  StakingRewardsDistributor public distributor;
  IERC20 public ldy;
  address public owner;
  address[] public actors;

  uint256[] public tokenIds;
  mapping(uint256 => uint256) public paidUpToWeek;

  uint256 public baseDeposited;
  uint256 public protocolDeposited;
  uint256 public rewardsPaid;

  constructor(
    StakingPositions staking_,
    StakingRewardsDistributor distributor_,
    address owner_
  ) {
    staking = staking_;
    distributor = distributor_;
    ldy = IERC20(staking_.token());
    owner = owner_;
    for (uint256 i; i < 4; i++)
      actors.push(address(uint160(0xA000 + i)));
    for (uint256 i; i < actors.length; i++) {
      vm.prank(actors[i]);
      ldy.approve(address(staking), type(uint256).max);
    }
    vm.prank(owner);
    ldy.approve(address(distributor), type(uint256).max);
  }

  function tokenCount() external view returns (uint256) {
    return tokenIds.length;
  }

  function _live(
    uint256 seed
  ) internal view returns (uint256 tokenId, bool found) {
    if (tokenIds.length == 0) return (0, false);
    for (uint256 i; i < tokenIds.length; i++) {
      tokenId = tokenIds[
        ((seed % tokenIds.length) + i) % tokenIds.length
      ];
      if (staking.ownerOf(tokenId) != address(0))
        return (tokenId, true);
    }
    return (0, false);
  }

  /// @dev First week the token is still owed, read without the distributor's cursor logic
  function _firstUnpaidWeek(
    uint256 tokenId
  ) internal view returns (uint256 week) {
    week = distributor.baseRewardCursor(tokenId);
    if (week == 0)
      week =
        (staking.getUserPointHistory(tokenId, 1).timestamp / WEEK) *
        WEEK;
    if (week < distributor.startTime())
      week = distributor.startTime();
  }

  function _model(
    uint256 tokenId,
    uint256 fromWeek,
    uint256 toWeek
  ) internal view returns (uint256 total) {
    uint256 periods = distributor.currentPeriodId();
    for (uint256 week = fromWeek; week < toWeek; week += WEEK) {
      uint256 weekly;
      for (uint256 p = 1; p <= periods; p++)
        weekly += distributor.baseRewardsPerWeek(p, week);
      if (weekly == 0) continue;
      uint256 supply = staking.totalSupplyAt(week + WEEK - 1);
      if (supply == 0) continue;
      total +=
        (staking.balanceOfNFTAt(tokenId, week + WEEK - 1) * weekly) /
        supply;
    }
  }

  // ======== ACTIONS ======== //

  function createLock(
    uint256 actorSeed,
    uint256 amount,
    uint256 duration
  ) external {
    if (tokenIds.length >= MAX_TOKENS) return;
    address actor = actors[actorSeed % actors.length];
    amount = bound(amount, 1 ether, 1_000_000 ether);
    duration = bound(duration, WEEK + 1, staking.maxTime());
    deal(address(ldy), actor, ldy.balanceOf(actor) + amount);
    vm.prank(actor);
    tokenIds.push(staking.createLock(amount, duration));
  }

  function increaseAmount(uint256 seed, uint256 amount) external {
    (uint256 tokenId, bool found) = _live(seed);
    if (!found) return;
    IStakingPositions.LockedBalance memory locked = staking
      .getLockedBalance(tokenId);
    if (locked.end <= block.timestamp) return;
    address holder = staking.ownerOf(tokenId);
    amount = bound(amount, 1 ether, 100_000 ether);
    deal(address(ldy), holder, ldy.balanceOf(holder) + amount);
    vm.startPrank(holder);
    ldy.approve(address(staking), type(uint256).max);
    staking.increaseAmount(tokenId, amount);
    vm.stopPrank();
  }

  function increaseUnlockTime(
    uint256 seed,
    uint256 duration
  ) external {
    (uint256 tokenId, bool found) = _live(seed);
    if (!found) return;
    IStakingPositions.LockedBalance memory locked = staking
      .getLockedBalance(tokenId);
    if (locked.end <= block.timestamp) return;
    duration = bound(duration, WEEK, staking.maxTime());
    uint256 unlockTime = ((block.timestamp + duration) / WEEK) * WEEK;
    if (unlockTime <= locked.end) return;
    vm.prank(staking.ownerOf(tokenId));
    staking.increaseUnlockTime(tokenId, duration);
  }

  function transferPosition(
    uint256 seed,
    uint256 actorSeed
  ) external {
    (uint256 tokenId, bool found) = _live(seed);
    if (!found) return;
    address from = staking.ownerOf(tokenId);
    address to = actors[actorSeed % actors.length];
    if (from == to) return;
    vm.prank(from);
    staking.transferFrom(from, to, tokenId);
  }

  function depositBaseRewards(
    uint256 amount,
    uint256 duration
  ) external {
    amount = bound(amount, 1 ether, 100_000 ether);
    duration = bound(duration, 1, 60);
    deal(address(ldy), owner, ldy.balanceOf(owner) + amount);
    vm.prank(owner);
    distributor.depositBaseRewards(amount, duration);
    baseDeposited += amount;
  }

  function depositProtocolFees(uint256 amount) external {
    amount = bound(amount, 1 ether, 100_000 ether);
    deal(address(ldy), owner, ldy.balanceOf(owner) + amount);
    vm.prank(owner);
    distributor.depositProtocolFees(amount);
    protocolDeposited += amount;
  }

  function setMaxTime(uint256 maxTime) external {
    maxTime = bound(maxTime, 8 * WEEK, 4 * 365 days);
    vm.prank(owner);
    staking.setMaxTime(maxTime);
  }

  function warp(uint256 seconds_) external {
    vm.warp(block.timestamp + bound(seconds_, 1 hours, 20 * WEEK));
    vm.roll(block.number + 1);
  }

  function claim(uint256 seed) external {
    (uint256 tokenId, bool found) = _live(seed);
    if (!found) return;
    _claimChecked(tokenId);
  }

  /// @dev One claim, checked against the model and the previous window
  function _claimChecked(uint256 tokenId) internal {
    uint256 fromWeek = _firstUnpaidWeek(tokenId);
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    uint256 toWeek = fromWeek + 50 * WEEK;
    if (toWeek > currentWeek) toWeek = currentWeek;
    uint256 expected = fromWeek < toWeek
      ? _model(tokenId, fromWeek, toWeek)
      : 0;

    if (paidUpToWeek[tokenId] != 0 && fromWeek < toWeek)
      assertEq(
        fromWeek,
        paidUpToWeek[tokenId],
        "claim window does not start where the last one ended"
      );

    vm.prank(staking.ownerOf(tokenId));
    (uint256 base, uint256 protocol) = distributor.claim(tokenId);
    rewardsPaid += base + protocol;
    assertEq(base, expected, "base rewards differ from the model");
    if (fromWeek < toWeek) {
      assertEq(
        distributor.baseRewardCursor(tokenId),
        toWeek,
        "cursor"
      );
      paidUpToWeek[tokenId] = toWeek;
    }
  }

  function withdraw(uint256 seed, bool claimFirst) external {
    (uint256 tokenId, bool found) = _live(seed);
    if (!found) return;
    IStakingPositions.LockedBalance memory locked = staking
      .getLockedBalance(tokenId);
    if (block.timestamp < locked.end) return;

    // Sometimes claim up to date first, sometimes let the withdrawal pay everything
    if (claimFirst) {
      for (uint256 i; i < 10; i++) {
        uint256 cursor = distributor.baseRewardCursor(tokenId);
        _claimChecked(tokenId);
        if (distributor.baseRewardCursor(tokenId) == cursor) break;
      }
    }

    // The withdrawal must pay every week still owed, plus the protocol fees accrued
    uint256 fromWeek = _firstUnpaidWeek(tokenId);
    uint256 currentWeek = (block.timestamp / WEEK) * WEEK;
    uint256 expectedBase = fromWeek < currentWeek
      ? _model(tokenId, fromWeek, currentWeek)
      : 0;
    (, uint256 expectedProtocol) = distributor.claimable(tokenId);

    address holder = staking.ownerOf(tokenId);
    uint256 before = ldy.balanceOf(holder);
    vm.prank(holder);
    staking.withdraw(tokenId);
    uint256 received = ldy.balanceOf(holder) - before;
    uint256 principal = uint256(int256(locked.amount));
    assertEq(
      received,
      principal + expectedBase + expectedProtocol,
      "withdrawal differs from principal plus the model"
    );
    rewardsPaid += received - principal;
  }
}

contract StakingRewardsInvariants is StdInvariant, Test {
  StakingPositions staking;
  StakingRewardsDistributor distributor;
  GenericERC20 ldy;
  StakingRewardsHandler handler;

  function setUp() public {
    GlobalOwner globalOwner = GlobalOwner(
      address(new ERC1967Proxy(address(new GlobalOwner()), ""))
    );
    GlobalPause globalPause = GlobalPause(
      address(new ERC1967Proxy(address(new GlobalPause()), ""))
    );
    GlobalAccessList accessList = GlobalAccessList(
      address(new ERC1967Proxy(address(new GlobalAccessList()), ""))
    );
    globalOwner.initialize();
    globalPause.initialize(address(globalOwner));
    accessList.initialize(address(globalOwner));

    ldy = new GenericERC20("Ledgity Token", "LDY", 18);
    staking = StakingPositions(
      address(new ERC1967Proxy(address(new StakingPositions()), ""))
    );
    distributor = StakingRewardsDistributor(
      address(
        new ERC1967Proxy(address(new StakingRewardsDistributor()), "")
      )
    );
    staking.initialize(
      address(ldy),
      address(distributor),
      4 * 365 days,
      address(globalOwner),
      address(globalPause),
      address(accessList)
    );
    distributor.initialize(
      address(staking),
      address(globalOwner),
      address(globalPause),
      address(accessList)
    );

    handler = new StakingRewardsHandler(
      staking,
      distributor,
      globalOwner.owner()
    );
    targetContract(address(handler));
  }

  function _liveTokens()
    internal
    view
    returns (uint256[] memory ids, uint256 n)
  {
    ids = new uint256[](handler.tokenCount());
    for (uint256 i; i < ids.length; i++) {
      uint256 id = handler.tokenIds(i);
      if (staking.ownerOf(id) != address(0)) ids[n++] = id;
    }
  }

  /// forge-config: default.invariant.runs = 64
  /// forge-config: default.invariant.depth = 80
  /// forge-config: default.invariant.fail-on-revert = true
  function invariant_distributorCoversEverythingClaimable()
    public
    view
  {
    (uint256[] memory ids, uint256 n) = _liveTokens();
    uint256 owed;
    for (uint256 i; i < n; i++) {
      (uint256 base, uint256 protocol) = distributor.claimable(
        ids[i]
      );
      owed += base + protocol;
    }
    assertLe(owed, ldy.balanceOf(address(distributor)));
  }

  /// forge-config: default.invariant.runs = 64
  /// forge-config: default.invariant.depth = 80
  /// forge-config: default.invariant.fail-on-revert = true
  function invariant_rewardsAccounting() public view {
    // LDY only enters through deposits and only leaves through claims and withdrawals
    assertEq(
      handler.baseDeposited() + handler.protocolDeposited(),
      ldy.balanceOf(address(distributor)) + handler.rewardsPaid()
    );
  }

  /// forge-config: default.invariant.runs = 64
  /// forge-config: default.invariant.depth = 80
  /// forge-config: default.invariant.fail-on-revert = true
  function invariant_principalAccounting() public view {
    (uint256[] memory ids, uint256 n) = _liveTokens();
    uint256 locked;
    for (uint256 i; i < n; i++)
      locked += uint256(
        int256(staking.getLockedBalance(ids[i]).amount)
      );
    assertEq(staking.supply(), locked, "supply vs locks");
    assertEq(
      ldy.balanceOf(address(staking)),
      locked,
      "LDY held vs locks"
    );
  }

  /// forge-config: default.invariant.runs = 64
  /// forge-config: default.invariant.depth = 80
  /// forge-config: default.invariant.fail-on-revert = true
  function invariant_votingPowerMatchesPositions() public view {
    (uint256[] memory ids, uint256 n) = _liveTokens();
    uint256 sum;
    for (uint256 i; i < n; i++)
      sum += staking.balanceOfNFTAt(ids[i], block.timestamp);
    assertApproxEqAbs(
      staking.totalSupplyAt(block.timestamp),
      sum,
      1e6
    );
  }
}
