// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { FixedTermInvestmentVault } from "src/protocol-v2/FixedTermInvestmentVault.sol";
import { LedgityDataProvider } from "src/protocol-v2/LedgityDataProvider.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { IGlobalAccessList } from "src/protocol-v2/interfaces/IGlobalAccessList.sol";

/**
 * @title Skip_VaultUpgradeSafeE2E
 * @notice Checks a vault upgrade executed through the real Safe on a local anvil fork by
 * `ledgity-api/scripts/rehearseMultisigBundle.ts`, by comparing the block just before the
 * execution with the block just after it:
 *   - every proxy points to the implementation of the bundle,
 *   - every raw storage slot is unchanged except the high-water mark, which holds the value
 *     of the bundle, and every getter returns the same value,
 *   - the deployed LedgityDataProvider returns after the upgrade exactly what the vault
 *     views returned before it,
 *   - the implementations cannot be initialized, the proxies not re-initialized, only the
 *     owner upgrades, and the owner can roll back to the previous implementation,
 *   - the fixed paths behave on the upgraded state (fee checkpoint, mark settled without a
 *     fee, duplicate request IDs, blacklisted shares, instant exits gated on the owner).
 *
 * @dev Env: ANVIL_URL, PRE_BLOCK, POST_BLOCK (printed by the rehearsal script), VAULTS,
 * NEW_IMPLS and MARKS (comma separated, same order), DATA_PROVIDER. Run with `--threads 1`.
 */
contract Skip_VaultUpgradeSafeE2E is Test {
  bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
  uint256 constant RAW_SLOTS = 520;

  uint256 preFork;
  uint256 postFork;
  address[] vaults;
  address[] newImpls;
  uint256[] marks;
  LedgityDataProvider dataProvider;

  function setUp() public {
    string memory url = vm.envString("ANVIL_URL");
    preFork = vm.createFork(url, vm.envUint("PRE_BLOCK"));
    postFork = vm.createFork(url, vm.envUint("POST_BLOCK"));
    vaults = vm.envAddress("VAULTS", ",");
    newImpls = vm.envAddress("NEW_IMPLS", ",");
    marks = vm.envUint("MARKS", ",");
    require(
      vaults.length == newImpls.length && vaults.length == marks.length,
      "env lengths"
    );
    dataProvider = LedgityDataProvider(vm.envAddress("DATA_PROVIDER"));
  }

  // ======== HELPERS ======== //

  function _implementation(address proxy) internal view returns (address) {
    return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
  }

  function _isFixedTerm(address vault) internal view returns (bool) {
    (bool ok, ) = vault.staticcall(abi.encodeWithSignature("operationEndDate()"));
    return ok;
  }

  function _settings(LedgityYieldVault v) internal view returns (bytes memory) {
    return
      abi.encode(
        v.name(),
        v.symbol(),
        v.asset(),
        address(v.lToken()),
        address(v.stakeToken()),
        v.stakeForFeeReduction(),
        v.stakeForInstantWithdrawal(),
        v.liquidityManager(),
        v.feeRecipient(),
        v.owner(),
        address(v.globalRestrict())
      );
  }

  /// @dev getBufferAssets() is compared apart: an Aave aToken balance grows every second
  function _buffer(LedgityYieldVault v) internal view returns (bytes memory) {
    return
      abi.encode(
        v.liquidityBufferRate(),
        v.hasBufferStrategy(),
        address(v.aaveLendingPool()),
        address(v.aToken())
      );
  }

  function _accounting(LedgityYieldVault v) internal view returns (bytes memory) {
    return
      abi.encode(
        v.totalSupply(),
        v.totalAssets(),
        v.lastCompoundTime(),
        v.lastFeeTime(),
        v.deploymentDelay(),
        v.yieldAPR(),
        v.decimalsOffset(),
        v.getWithdrawalRequestCount(),
        v.balanceOf(v.feeRecipient())
      );
  }

  function _fees(LedgityYieldVault v) internal view returns (bytes memory) {
    return
      abi.encode(
        v.managementFeeRate(),
        v.performanceFeeRate(),
        v.withdrawalFeeRate(),
        v.withdrawalGasFee()
      );
  }

  /// @dev Every getter compared across the execution, the high-water mark and the buffer
  ///      balance aside
  function _getters(address vault) internal view returns (bytes32) {
    LedgityYieldVault v = LedgityYieldVault(vault);
    return keccak256(abi.encode(_settings(v), _buffer(v), _accounting(v), _fees(v)));
  }

  /// @dev The same getters by group, so a mismatch names its group
  function _getterGroups(address vault) internal view returns (bytes32[4] memory groups) {
    LedgityYieldVault v = LedgityYieldVault(vault);
    groups[0] = keccak256(_settings(v));
    groups[1] = keccak256(_buffer(v));
    groups[2] = keccak256(_accounting(v));
    groups[3] = keccak256(_fees(v));
  }

  function _rawStorage(address vault) internal view returns (bytes32[] memory slots) {
    slots = new bytes32[](RAW_SLOTS);
    for (uint256 s; s < RAW_SLOTS; s++) slots[s] = vm.load(vault, bytes32(s));
  }

  function _liveView(
    address vault,
    bool onlyPending
  ) internal view returns (bool ok, ILedgityDataProvider.WithdrawalRequestRead[] memory requests) {
    bytes memory data;
    (ok, data) = vault.staticcall(
      abi.encodeWithSignature("getWithdrawalRequests(bool,uint256)", onlyPending, uint256(0))
    );
    if (ok) requests = abi.decode(data, (ILedgityDataProvider.WithdrawalRequestRead[]));
  }

  function _assertSameRequests(
    ILedgityDataProvider.WithdrawalRequestRead[] memory a,
    ILedgityDataProvider.WithdrawalRequestRead[] memory b
  ) internal pure {
    assertEq(a.length, b.length, "request count");
    for (uint256 r; r < a.length; r++) {
      assertEq(a[r].requestId, b[r].requestId, "requestId");
      assertEq(a[r].user, b[r].user, "user");
      assertEq(a[r].amount, b[r].amount, "amount");
      assertEq(a[r].timestamp, b[r].timestamp, "timestamp");
      assertEq(a[r].processed, b[r].processed, "processed");
      assertEq(a[r].hasFeeReduction, b[r].hasFeeReduction, "hasFeeReduction");
    }
  }

  // ======== PER VAULT CHECKS ======== //

  function _checkStorage(uint256 i) internal {
    address vault = vaults[i];
    vm.selectFork(preFork);
    bytes32[] memory pre = _rawStorage(vault);
    bytes32[4] memory groupsPre = _getterGroups(vault);
    uint256 bufferPre = LedgityYieldVault(vault).getBufferAssets();
    uint256 markPre = LedgityYieldVault(vault).highWaterMark();
    (, uint256 pricePre) = LedgityYieldVault(vault).getFeeData();

    vm.selectFork(postFork);
    bytes32[] memory post = _rawStorage(vault);
    uint256 changed;
    for (uint256 s; s < RAW_SLOTS; s++) {
      if (post[s] == pre[s]) continue;
      changed++;
      // The only slot the bundle writes: the high-water mark
      assertEq(uint256(pre[s]), markPre, string.concat("slot ", vm.toString(s), " changed"));
      assertEq(uint256(post[s]), marks[i], "mark of the bundle");
    }
    assertLe(changed, 1, "more than one slot changed");
    assertEq(LedgityYieldVault(vault).highWaterMark(), marks[i], "mark");
    bytes32[4] memory groupsPost = _getterGroups(vault);
    assertEq(groupsPost[0], groupsPre[0], "getters: settings");
    assertEq(groupsPost[1], groupsPre[1], "getters: buffer strategy");
    assertEq(groupsPost[2], groupsPre[2], "getters: accounting");
    assertEq(groupsPost[3], groupsPre[3], "getters: fees");
    // Aave interest only: never lower, at most a hundred-thousandth higher over the gap
    uint256 bufferPost = LedgityYieldVault(vault).getBufferAssets();
    assertGe(bufferPost, bufferPre, "buffer lower");
    assertLe(bufferPost - bufferPre, bufferPre / 100_000 + 1, "buffer moved more than interest");
    emit log_named_uint(string.concat("buffer interest over the gap, vault ", vm.toString(i)), bufferPost - bufferPre);
    (, uint256 pricePost) = LedgityYieldVault(vault).getFeeData();
    assertApproxEqAbs(pricePost, pricePre, 1, "price per share");
  }

  function _checkDataProvider(uint256 i) internal {
    address vault = vaults[i];
    vm.selectFork(preFork);
    (bool ok, ILedgityDataProvider.WithdrawalRequestRead[] memory all) = _liveView(vault, false);
    assertTrue(ok, "pre: the view answers");
    (, ILedgityDataProvider.WithdrawalRequestRead[] memory pending) = _liveView(vault, true);
    uint256 count = LedgityYieldVault(vault).getWithdrawalRequestCount();

    vm.selectFork(postFork);
    (ok, ) = _liveView(vault, false);
    assertFalse(ok, "post: the vault view is gone");
    _assertSameRequests(all, dataProvider.getWithdrawalRequests(vault, false, 0));
    _assertSameRequests(pending, dataProvider.getWithdrawalRequests(vault, true, 0));
    assertEq(all.length, count, "every request");
  }

  function _checkHygiene(uint256 i) internal {
    ILedgityYieldVault.VaultParams memory params;
    IVaultLiquidityModule.VaultLiquidityInitParams memory liquidityParams;
    vm.selectFork(postFork);
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    ILedgityYieldVault(newImpls[i]).initialize(params, liquidityParams);
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    ILedgityYieldVault(vaults[i]).initialize(params, liquidityParams);
    vm.expectRevert(bytes("Function must be called through delegatecall"));
    UUPSUpgradeable(newImpls[i]).upgradeTo(address(0xBAD));
  }

  function _checkRollback(uint256 i) internal {
    address vault = vaults[i];
    vm.selectFork(preFork);
    address previous = _implementation(vault);
    vm.selectFork(postFork);
    address owner = LedgityYieldVault(vault).owner();

    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    vm.prank(address(0xBAD));
    UUPSUpgradeable(vault).upgradeTo(previous);

    uint256 snapshot = vm.snapshotState();
    bytes32 getters = _getters(vault);
    vm.prank(owner);
    UUPSUpgradeable(vault).upgradeTo(previous);
    assertEq(_implementation(vault), previous, "rolled back");
    assertEq(_getters(vault), getters, "getters after rollback");
    (bool ok, ) = _liveView(vault, false);
    assertTrue(ok, "the old view answers again");
    vm.revertToState(snapshot);
  }

  function _checkCheckpointAndMark(LedgityYieldVault v) internal {
    uint256 recipientShares = v.balanceOf(v.feeRecipient());
    vm.warp(block.timestamp + 2 days);
    v.harvestFees();
    assertEq(v.lastFeeTime(), block.timestamp, "checkpoint advanced");
    (, uint256 price) = v.getFeeData();
    assertGe(v.highWaterMark(), price, "mark at or above the price");
    assertLe(v.highWaterMark() - price, 1, "mark on the price");
    assertEq(v.balanceOf(v.feeRecipient()), recipientShares, "no fee taken");
  }

  /// @dev Liquidity in the buffer and a deposit; false when Aave refuses supplies (Sonic today)
  function _fund(LedgityYieldVault v, address user) internal returns (bool) {
    IERC20 asset = IERC20(v.asset());
    uint256 unit = 10 ** IERC20Metadata(address(asset)).decimals();
    address manager = v.liquidityManager();
    deal(address(asset), manager, asset.balanceOf(manager) + 1_000 * unit);
    vm.startPrank(manager);
    asset.approve(address(v), type(uint256).max);
    (bool topUp, ) = address(v).call(abi.encodeCall(v.depositToBuffer, (1_000 * unit)));
    vm.stopPrank();
    deal(address(asset), user, 100 * unit);
    vm.startPrank(user);
    asset.approve(address(v), type(uint256).max);
    (bool deposited, ) = address(v).call(abi.encodeCall(v.deposit, (100 * unit, user)));
    vm.stopPrank();
    return topUp && deposited;
  }

  function _checkRequestPaidOnce(LedgityYieldVault v, address user) internal {
    uint256 gasFee = v.withdrawalGasFee();
    uint256 shares = v.balanceOf(user) / 2;
    vm.deal(user, gasFee);
    vm.prank(user);
    v.requestWithdrawal{ value: gasFee }(shares);
    uint256[] memory twice = new uint256[](2);
    twice[0] = v.getWithdrawalRequestCount() - 1;
    twice[1] = twice[0];
    address manager = v.liquidityManager();
    vm.prank(manager);
    vm.expectRevert(LedgityYieldVault.RequestAlreadyProcessed.selector);
    v.processRequests(twice, 0);
    uint256[] memory once = new uint256[](1);
    once[0] = twice[0];
    vm.prank(manager);
    v.processRequests(once, 0);
    assertTrue(dataProvider.getWithdrawalRequestsByIds(address(v), once)[0].processed, "paid");
  }

  function _checkBlacklistedShares(LedgityYieldVault v, address user) internal {
    address owner = v.owner();
    IGlobalAccessList accessList = v.globalRestrict();
    vm.prank(owner);
    accessList.restrictAccount(user);
    uint256 left = v.balanceOf(user);
    uint256 ownerBefore = v.balanceOf(owner);
    vm.prank(owner);
    v.burnAndRemintBlacklistedShares(user, owner);
    assertEq(v.balanceOf(user), 0, "restricted balance moved");
    assertEq(v.balanceOf(owner) - ownerBefore, left, "reminted");
  }

  // ======== TESTS ======== //

  function test_e2e_implementationsAreTheBundle() public {
    for (uint256 i; i < vaults.length; i++) {
      vm.selectFork(preFork);
      assertTrue(_implementation(vaults[i]) != newImpls[i], "pre: already upgraded");
      vm.selectFork(postFork);
      assertEq(_implementation(vaults[i]), newImpls[i], "implementation");
      assertGt(newImpls[i].code.length, 0, "implementation code");
    }
  }

  function test_e2e_storageSameExceptTheMark() public {
    for (uint256 i; i < vaults.length; i++) _checkStorage(i);
  }

  function test_e2e_dataProviderEqualsTheOldViews() public {
    for (uint256 i; i < vaults.length; i++) _checkDataProvider(i);
  }

  function test_e2e_proxyHygieneAndRollback() public {
    for (uint256 i; i < vaults.length; i++) {
      _checkHygiene(i);
      _checkRollback(i);
    }
  }

  function test_e2e_fixesOnTheUpgradedState() public {
    vm.selectFork(postFork);
    for (uint256 i; i < vaults.length; i++) {
      LedgityYieldVault v = LedgityYieldVault(vaults[i]);
      uint256 snapshot = vm.snapshotState();
      _checkCheckpointAndMark(v);
      address user = makeAddr(string.concat("user", vm.toString(i)));
      if (_fund(v, user)) {
        _checkRequestPaidOnce(v, user);
        _checkBlacklistedShares(v, user);
      } else {
        emit log_named_address("deposit flows skipped, Aave refuses supplies", address(v));
      }
      if (_isFixedTerm(address(v))) {
        vm.expectRevert(FixedTermInvestmentVault.NoLTokenSet.selector);
        FixedTermInvestmentVault(address(v)).migrateLToken(1);
      }
      vm.revertToState(snapshot);
    }
  }

  /// @dev An allowance holder with the stake cannot relay an instant exit for an owner without it
  function test_e2e_instantExitGatedOnTheOwner() public {
    vm.selectFork(postFork);
    for (uint256 i; i < vaults.length; i++) {
      LedgityYieldVault v = LedgityYieldVault(vaults[i]);
      address stakeToken = address(v.stakeToken());
      uint256 threshold = v.stakeForInstantWithdrawal();
      if (threshold == 0 || stakeToken == address(0)) continue;
      uint256 snapshot = vm.snapshotState();
      address holder = makeAddr(string.concat("holder", vm.toString(i)));
      address relayer = makeAddr(string.concat("relayer", vm.toString(i)));
      deal(address(v), holder, 1e18);
      vm.prank(holder);
      v.approve(relayer, type(uint256).max);
      vm.mockCall(stakeToken, abi.encodeWithSelector(IERC20.balanceOf.selector, relayer), abi.encode(threshold));
      vm.mockCall(stakeToken, abi.encodeWithSelector(IERC20.balanceOf.selector, holder), abi.encode(uint256(0)));
      vm.expectRevert(LedgityYieldVault.InsufficientStakeForInstantWithdrawal.selector);
      vm.prank(relayer);
      v.redeem(1e18, relayer, holder);
      vm.clearMockedCalls();
      vm.revertToState(snapshot);
    }
  }
}
