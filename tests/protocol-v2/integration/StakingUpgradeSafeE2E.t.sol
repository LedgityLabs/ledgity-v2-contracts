// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC1822ProxiableUpgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StakingPositions } from "src/protocol-v2/staking/StakingPositions.sol";
import { StakingRewardsDistributor } from "src/protocol-v2/staking/StakingRewardsDistributor.sol";
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";

/**
 * @title Skip_StakingUpgradeSafeE2E
 * @notice Checks a staking upgrade executed through the real Safe on a local anvil fork by
 * `ledgity-api/scripts/rehearseMultisigBundle.ts`, by comparing the block just before the
 * execution with the block just after it:
 *   - the proxies point to the implementations of the bundle, and only there,
 *   - every getter returns the same bytes AND reads the same storage slots for every live
 *     position (a shifted layout cannot pass with equal values),
 *   - the implementations cannot be initialized, the proxies not re-initialized, only the
 *     owner upgrades,
 *   - claims, withdrawals, new locks and fee deposits work after the upgrade.
 *
 * @dev Env: ANVIL_URL, PRE_BLOCK, POST_BLOCK (printed by the rehearsal script), STAKING_PROXY,
 * NEW_STAKING_IMPL, NEW_DISTRIBUTOR_IMPL. Run with `--threads 1`.
 */
contract Skip_StakingUpgradeSafeE2E is Test {
  uint256 constant WEEK = 1 weeks;
  bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  uint256 preFork;
  uint256 postFork;
  StakingPositions staking;
  StakingRewardsDistributor distributor;
  address newStakingImpl;
  address newDistributorImpl;

  struct Probe {
    address target;
    bytes call;
    // Values may legitimately differ after the upgrade (only checked for reads)
    bool skipValue;
    // Reads may legitimately differ (new code path), only the value is checked
    bool skipReads;
  }

  function setUp() public {
    string memory url = vm.envString("ANVIL_URL");
    preFork = vm.createFork(url, vm.envUint("PRE_BLOCK"));
    postFork = vm.createFork(url, vm.envUint("POST_BLOCK"));
    staking = StakingPositions(vm.envAddress("STAKING_PROXY"));
    newStakingImpl = vm.envAddress("NEW_STAKING_IMPL");
    newDistributorImpl = vm.envAddress("NEW_DISTRIBUTOR_IMPL");
    vm.selectFork(postFork);
    distributor = StakingRewardsDistributor(
      staking.rewardsDistributor()
    );
  }

  function _implementation(
    address proxy
  ) internal view returns (address) {
    return
      address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
  }

  /// @dev Return data and storage slots read by one static call
  function _probe(
    Probe memory probe
  ) internal returns (bytes memory ret, bytes32[] memory reads) {
    vm.record();
    bool ok;
    (ok, ret) = probe.target.staticcall(probe.call);
    require(ok, "probe reverted");
    (reads, ) = vm.accesses(probe.target);
  }

  function _probes() internal view returns (Probe[] memory probes) {
    uint256 lastId = staking.tokenId();
    uint256 periods = distributor.currentPeriodId();
    probes = new Probe[](15 + lastId * 11 + periods * 3);
    uint256 n;
    address s = address(staking);
    address d = address(distributor);

    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.epoch, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.supply, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.maxTime, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.iMaxTime, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.tokenId, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.token, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.rewardsDistributor, ()),
      false,
      false
    );
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.breaker, ()),
      false,
      false
    );
    // Voting power decays every second: probed at the pre-upgrade timestamp in both blocks
    probes[n++] = Probe(
      s,
      abi.encodeCall(staking.totalSupplyAt, (block.timestamp)),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(distributor.staking, ()),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(distributor.token, ()),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(distributor.startTime, ()),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(distributor.lastTokenTime, ()),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(distributor.currentPeriodId, ()),
      false,
      false
    );
    probes[n++] = Probe(
      d,
      abi.encodeCall(
        distributor.cumulativeProtocolRewardsPerToken,
        ()
      ),
      false,
      false
    );

    for (uint256 p = 1; p <= periods; p++) {
      (uint256 startWeek, , , ) = distributor.baseRewardPeriods(p);
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.baseRewardPeriods, (p)),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(
          distributor.baseRewardsPerWeek,
          (p, startWeek)
        ),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(
          distributor.baseRewardsPerWeek,
          (p, startWeek + 10 * WEEK)
        ),
        false,
        false
      );
    }

    for (uint256 id = 1; id <= lastId; id++) {
      probes[n++] = Probe(
        s,
        abi.encodeCall(staking.ownerOf, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        s,
        abi.encodeCall(staking.getLockedBalance, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        s,
        abi.encodeCall(staking.userPointEpoch, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        s,
        abi.encodeCall(
          staking.getUserPointHistory,
          (id, staking.userPointEpoch(id))
        ),
        false,
        false
      );
      probes[n++] = Probe(
        s,
        abi.encodeCall(staking.balanceOfNFTAt, (id, block.timestamp)),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.baseRewardCursor, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.protocolRewardCursor, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.protocolRewardsPerTokenPaid, (id)),
        false,
        false
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.accruedProtocolRewards, (id)),
        false,
        false
      );
      // The period cursor moved to a new mapping by design; claimable runs a new code path
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.baseRewardPeriodCursor, (id)),
        true,
        true
      );
      probes[n++] = Probe(
        d,
        abi.encodeCall(distributor.claimable, (id)),
        true,
        true
      );
    }
    assembly {
      mstore(probes, n)
    }
  }

  function test_e2e_implementationsAreTheBundle() public {
    vm.selectFork(preFork);
    address oldStakingImpl = _implementation(address(staking));
    address oldDistributorImpl = _implementation(
      address(distributor)
    );
    assertTrue(
      oldStakingImpl != newStakingImpl,
      "pre: already upgraded"
    );
    assertTrue(
      oldDistributorImpl != newDistributorImpl,
      "pre: already upgraded"
    );

    vm.selectFork(postFork);
    assertEq(
      _implementation(address(staking)),
      newStakingImpl,
      "staking implementation"
    );
    assertEq(
      _implementation(address(distributor)),
      newDistributorImpl,
      "distributor implementation"
    );
    assertGt(newStakingImpl.code.length, 0);
    assertGt(newDistributorImpl.code.length, 0);
  }

  function test_e2e_everyGetterSameValueAndSameSlots() public {
    vm.selectFork(preFork);
    Probe[] memory probes = _probes();
    bytes[] memory values = new bytes[](probes.length);
    bytes32[][] memory slots = new bytes32[][](probes.length);
    for (uint256 i; i < probes.length; i++)
      (values[i], slots[i]) = _probe(probes[i]);

    vm.selectFork(postFork);
    for (uint256 i; i < probes.length; i++) {
      (bytes memory value, bytes32[] memory read) = _probe(probes[i]);
      if (!probes[i].skipValue)
        assertEq(
          value,
          values[i],
          string.concat("value changed, probe ", vm.toString(i))
        );
      if (!probes[i].skipReads) {
        assertEq(
          read.length,
          slots[i].length,
          string.concat("slots read changed, probe ", vm.toString(i))
        );
        for (uint256 j; j < read.length; j++)
          assertEq(
            read[j],
            slots[i][j],
            string.concat("slot read changed, probe ", vm.toString(i))
          );
      }
    }

    // Protocol rewards claimable unchanged, base rewards claimable never lower
    for (uint256 id = 1; id <= staking.tokenId(); id++) {
      vm.selectFork(preFork);
      (uint256 baseBefore, uint256 protocolBefore) = distributor
        .claimable(id);
      vm.selectFork(postFork);
      (uint256 baseAfter, uint256 protocolAfter) = distributor
        .claimable(id);
      assertEq(protocolAfter, protocolBefore, "protocol claimable");
      assertGe(baseAfter, baseBefore, "base claimable decreased");
    }
  }

  function test_e2e_proxyHygiene() public {
    vm.selectFork(postFork);
    address safe = staking.owner();

    // Implementations cannot be initialized by anyone
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    StakingPositions(newStakingImpl).initialize(
      address(1),
      address(1),
      1,
      address(1),
      address(1),
      address(1)
    );
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    StakingRewardsDistributor(newDistributorImpl).initialize(
      address(1),
      address(1),
      address(1),
      address(1)
    );

    // Proxies cannot be re-initialized, not even by the owner
    vm.startPrank(safe);
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    staking.initialize(
      address(1),
      address(1),
      1,
      address(1),
      address(1),
      address(1)
    );
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    distributor.initialize(
      address(1),
      address(1),
      address(1),
      address(1)
    );
    vm.stopPrank();

    // UUPS identity and upgrade authorization
    assertEq(
      IERC1822ProxiableUpgradeable(newStakingImpl).proxiableUUID(),
      IMPLEMENTATION_SLOT
    );
    assertEq(
      IERC1822ProxiableUpgradeable(newDistributorImpl)
        .proxiableUUID(),
      IMPLEMENTATION_SLOT
    );
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    vm.prank(address(0xBAD));
    UUPSUpgradeable(address(staking)).upgradeTo(newStakingImpl);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    vm.prank(address(0xBAD));
    UUPSUpgradeable(address(distributor)).upgradeTo(
      newDistributorImpl
    );
    vm.expectRevert(
      bytes("Function must be called through delegatecall")
    );
    UUPSUpgradeable(newStakingImpl).upgradeTo(newStakingImpl);
  }

  function test_e2e_postUpgradeSmoke() public {
    vm.selectFork(postFork);
    IERC20 ldy = IERC20(staking.token());
    uint256 lastId = staking.tokenId();

    // Every position claims, then claims again for nothing
    for (uint256 id = 1; id <= lastId; id++) {
      address owner = staking.ownerOf(id);
      if (owner == address(0)) continue;
      vm.prank(owner);
      distributor.claim(id);
      if (
        distributor.baseRewardCursor(id) <
        (block.timestamp / WEEK) * WEEK
      ) continue;
      vm.prank(owner);
      (uint256 base, uint256 protocol) = distributor.claim(id);
      assertEq(base + protocol, 0, "claimed twice");
    }

    // A new staker locks, adds, extends
    address staker = makeAddr("newStaker");
    deal(address(ldy), staker, 1000 ether);
    vm.startPrank(staker);
    ldy.approve(address(staking), type(uint256).max);
    uint256 tokenId = staking.createLock(500 ether, 52 * WEEK);
    staking.increaseAmount(tokenId, 100 ether);
    staking.increaseUnlockTime(tokenId, 104 * WEEK);
    vm.stopPrank();
    assertEq(staking.ownerOf(tokenId), staker);

    // The owner deposits protocol fees, the new staker gets a share a week later
    address safe = staking.owner();
    deal(address(ldy), safe, 100 ether);
    vm.startPrank(safe);
    ldy.approve(address(distributor), type(uint256).max);
    distributor.depositProtocolFees(100 ether);
    vm.stopPrank();
    vm.warp(block.timestamp + WEEK);
    (, uint256 protocolShare) = distributor.claimable(tokenId);
    assertGt(protocolShare, 0, "protocol fees not shared");

    // Every lock past its end withdraws its exact principal
    vm.warp(block.timestamp + 5 * 52 * WEEK);
    for (uint256 id = 1; id <= staking.tokenId(); id++) {
      address owner = staking.ownerOf(id);
      if (owner == address(0)) continue;
      IStakingPositions.LockedBalance memory locked = staking
        .getLockedBalance(id);
      uint256 before = ldy.balanceOf(owner);
      vm.prank(owner);
      staking.withdraw(id);
      assertGe(
        ldy.balanceOf(owner) - before,
        uint256(int256(locked.amount)),
        "principal"
      );
    }
    assertEq(staking.supply(), 0, "principal left in staking");
  }
}
