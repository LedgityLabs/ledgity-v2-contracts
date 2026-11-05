// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { LedgityYieldVaultSonic } from "src/protocol-v2/chainSonic/LedgityYieldVaultSonic.sol";
import { FixedTermInvestmentVault } from "src/protocol-v2/FixedTermInvestmentVault.sol";
import { LedgityDataProvider } from "src/protocol-v2/LedgityDataProvider.sol";
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { IGlobalAccessList } from "src/protocol-v2/interfaces/IGlobalAccessList.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

/**
 * @title Skip_VaultFixesUpgradeFork
 * @notice Rehearses the vault maintenance upgrade on a fork of the target chain: the live
 * proxies are pointed at the new implementation by their owner, then `updateHighWaterMark`
 * resets the mark to the live price. Checks that the storage and every getter survive, that
 * the standalone LedgityDataProvider returns what the removed vault views returned, that the
 * upgrade can be rolled back, and that each fixed path behaves (fee checkpoint, duplicate
 * request IDs, blacklisted shares). Two tests rehearse the withdrawal fee alignment planned
 * for the V3 launch (`updateVaultParams` with the 50k veLDY threshold), which is not in the
 * bundle: the setter leaves the Aave buffer in place, the fee is charged below the threshold
 * and waived above.
 *
 * @dev Skipped by the default suites (Skip_ prefix). Run one chain at a time with
 * `npm run test:upgrade-vaults:<chain>`, which sets HARDHAT_DEPLOY_FORK and expects
 * <CHAIN>_RPC_URL (and optionally <CHAIN>_FORKING_BLOCK) in the environment.
 */
contract Skip_VaultFixesUpgradeFork is Test {
  using Math for uint256;

  struct Target {
    address vault;
    bool fixedTerm;
  }

  struct Snapshot {
    string name;
    string symbol;
    address asset;
    address lToken;
    address stakeToken;
    uint256 stakeForFeeReduction;
    uint256 stakeForInstantWithdrawal;
    address liquidityManager;
    address feeRecipient;
    uint256 liquidityBufferRate;
    bool hasBufferStrategy;
    address aaveLendingPool;
    address aToken;
    address owner;
    address globalRestrict;
    uint256 totalSupply;
    uint256 totalAssets;
    uint256 lastCompoundTime;
    uint256 lastFeeTime;
    uint256 highWaterMark;
    uint8 deploymentDelay;
    uint256 yieldAPR;
    uint256 managementFeeRate;
    uint256 performanceFeeRate;
    uint256 withdrawalFeeRate;
    uint256 withdrawalGasFee;
    uint8 decimalsOffset;
    uint256 bufferAssets;
    uint256 requestCount;
    uint256 feeShares;
    uint256 pricePerShare;
    uint256 assetsPerShare;
    uint256 feeRecipientShares;
  }

  uint256 constant STAKE_FOR_FEE_REDUCTION = 50_000 ether;
  uint256 constant RAY = 1e27;
  /// @dev Raw storage slots compared across the upgrade (the vault layout ends before slot 480)
  uint256 constant RAW_SLOTS = 520;
  bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  Target[] targets;
  address stakeToken;
  bool isSonic;
  /// @dev Aave refuses supplies on the chain (Sonic: the USDC reserve is frozen, supply cap 1),
  ///      so the flows run on an idle buffer, which also rehearses the pool switch on live state
  bool detachBuffer;
  address yieldImplementation;
  address fixedTermImplementation;
  LedgityDataProvider dataProvider;
  address user;
  address other;

  function setUp() public {
    string memory fork = vm.envOr("HARDHAT_DEPLOY_FORK", string("base"));

    if (_eq(fork, "mainnet")) {
      _fork("MAINNET");
      targets.push(Target(0x3C769d0e8D21d380228dFB7918c6933bb6ecB6D4, false)); // lyUSD
      targets.push(Target(0x20968165B7d2cDF33aF632aAB3e0539848d44BC8, false)); // lyEUR
      stakeToken = 0xEB4B058BF032E1eD61AA1fEcA332a8b8b96F7483;
    } else if (_eq(fork, "base")) {
      _fork("BASE");
      targets.push(Target(0x916f179D5D9B7d8Ad815AC2f8570aabF0C6a6e38, false)); // lyUSD
      targets.push(Target(0xFaA1e3720e6Ef8cC76A800DB7B3dF8944833b134, false)); // lyEUR
      targets.push(Target(0x085b292A7c54767d5371fE939a4Ad4dC9828d98f, true)); // lyREI
      stakeToken = 0x0fCfdF9B6572116FA662A5CF8a074B51EB2D6d88;
    } else if (_eq(fork, "arbitrum")) {
      _fork("ARBITRUM");
      targets.push(Target(0x283F35b6406a0e19a786ed119869eF2c0fE157Ee, false)); // lyUSD
      stakeToken = 0x6E83612c73f124127d49eA642c392FF4d9eAFd5b;
    } else if (_eq(fork, "linea")) {
      _fork("LINEA");
      targets.push(Target(0x43b3c64dbc95F9eD83795E051fc00014059e698F, false)); // lyUSD
      // The StakingPositions proxy (deployers/deployments/linea/StakingPositions.json records
      // the implementation): the vault has no stakeToken today
      stakeToken = 0xcc1beF907DCe6c073332A75086708F53BDe4f6f0;
    } else if (_eq(fork, "sonic")) {
      _fork("SONIC");
      targets.push(Target(0x65f75c675Cc76474662DfBF7B6e8683764223001, false)); // lyUSD
      stakeToken = 0x613904B9a1Af4450FD34655d123EEb0944888b21;
      isSonic = true;
      detachBuffer = true;
    } else {
      revert(string.concat("Unsupported fork target: ", fork));
    }

    yieldImplementation = isSonic
      ? address(new LedgityYieldVaultSonic())
      : address(new LedgityYieldVault());
    fixedTermImplementation = address(new FixedTermInvestmentVault());
    dataProvider = new LedgityDataProvider();
    user = makeAddr("user");
    other = makeAddr("other");
    vm.label(yieldImplementation, "LedgityYieldVault (fixes)");
    vm.label(fixedTermImplementation, "FixedTermInvestmentVault (fixes)");
  }

  // ======== HELPERS ======== //

  function _fork(string memory prefix) internal {
    string memory rpcUrl = vm.envString(string.concat(prefix, "_RPC_URL"));
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

  function _eq(
    string memory a,
    string memory b
  ) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  function _vault(uint256 i) internal view returns (LedgityYieldVault) {
    // The fixed-term vault shares every function used here with the yield vault
    return LedgityYieldVault(targets[i].vault);
  }

  function _implementation(uint256 i) internal view returns (address) {
    return targets[i].fixedTerm ? fixedTermImplementation : yieldImplementation;
  }

  function _upgrade(uint256 i) internal {
    address owner = _vault(i).owner();
    vm.prank(owner);
    UUPSUpgradeable(targets[i].vault).upgradeTo(_implementation(i));
  }

  /// @dev The withdrawal fee alignment planned for the V3 launch (Pierre-Yves, 2026-11-05),
  ///      not part of the maintenance bundle: the live params, the 50k threshold and the
  ///      chain's StakingPositions as stake token
  function _applyFeeReduction(uint256 i) internal {
    LedgityYieldVault vault = _vault(i);
    IERC20 lToken = vault.lToken();
    uint256 stakeForInstantWithdrawal = vault.stakeForInstantWithdrawal();
    address pool = address(vault.aaveLendingPool());
    address owner = vault.owner();

    vm.prank(owner);
    vault.updateVaultParams(
      lToken,
      IERC20(stakeToken),
      STAKE_FOR_FEE_REDUCTION,
      stakeForInstantWithdrawal,
      IAaveLendingPoolV3(pool)
    );
    assertEq(address(vault.aaveLendingPool()), pool, "pool unchanged");
  }

  /// @dev The second transaction of each bundle: the mark reset to the price read when the
  ///      bundle is built, i.e. from the live implementation
  function _resetHighWaterMark(uint256 i, uint256 priceWhenBuilt) internal {
    LedgityYieldVault vault = _vault(i);
    address owner = vault.owner();
    vm.prank(owner);
    vault.updateHighWaterMark(priceWhenBuilt);
  }

  function _rawStorage(
    address vault
  ) internal view returns (bytes32[] memory slots) {
    slots = new bytes32[](RAW_SLOTS);
    for (uint256 s; s < RAW_SLOTS; s++) slots[s] = vm.load(vault, bytes32(s));
  }

  function _snapshot(uint256 i) internal view returns (Snapshot memory s) {
    LedgityYieldVault vault = _vault(i);
    s.name = vault.name();
    s.symbol = vault.symbol();
    s.asset = vault.asset();
    s.lToken = address(vault.lToken());
    s.stakeToken = address(vault.stakeToken());
    s.stakeForFeeReduction = vault.stakeForFeeReduction();
    s.stakeForInstantWithdrawal = vault.stakeForInstantWithdrawal();
    s.liquidityManager = vault.liquidityManager();
    s.feeRecipient = vault.feeRecipient();
    s.liquidityBufferRate = vault.liquidityBufferRate();
    s.hasBufferStrategy = vault.hasBufferStrategy();
    s.aaveLendingPool = address(vault.aaveLendingPool());
    s.aToken = address(vault.aToken());
    s.owner = vault.owner();
    s.globalRestrict = address(vault.globalRestrict());
    s.totalSupply = vault.totalSupply();
    s.totalAssets = vault.totalAssets();
    s.lastCompoundTime = vault.lastCompoundTime();
    s.lastFeeTime = vault.lastFeeTime();
    s.highWaterMark = vault.highWaterMark();
    s.deploymentDelay = vault.deploymentDelay();
    s.yieldAPR = vault.yieldAPR();
    s.managementFeeRate = vault.managementFeeRate();
    s.performanceFeeRate = vault.performanceFeeRate();
    s.withdrawalFeeRate = vault.withdrawalFeeRate();
    s.withdrawalGasFee = vault.withdrawalGasFee();
    s.decimalsOffset = vault.decimalsOffset();
    s.bufferAssets = vault.getBufferAssets();
    s.requestCount = vault.getWithdrawalRequestCount();
    (s.feeShares, s.pricePerShare) = vault.getFeeData();
    s.assetsPerShare = vault.convertToAssets(1e18);
    s.feeRecipientShares = vault.balanceOf(vault.feeRecipient());
  }

  function _assertSame(Snapshot memory a, Snapshot memory b) internal pure {
    assertEq(a.name, b.name, "name");
    assertEq(a.symbol, b.symbol, "symbol");
    assertEq(a.asset, b.asset, "asset");
    assertEq(a.lToken, b.lToken, "lToken");
    assertEq(a.stakeToken, b.stakeToken, "stakeToken");
    assertEq(a.stakeForFeeReduction, b.stakeForFeeReduction, "stakeForFeeReduction");
    assertEq(a.stakeForInstantWithdrawal, b.stakeForInstantWithdrawal, "stakeForInstantWithdrawal");
    assertEq(a.liquidityManager, b.liquidityManager, "liquidityManager");
    assertEq(a.feeRecipient, b.feeRecipient, "feeRecipient");
    assertEq(a.liquidityBufferRate, b.liquidityBufferRate, "liquidityBufferRate");
    assertEq(a.hasBufferStrategy, b.hasBufferStrategy, "hasBufferStrategy");
    assertEq(a.aaveLendingPool, b.aaveLendingPool, "aaveLendingPool");
    assertEq(a.aToken, b.aToken, "aToken");
    assertEq(a.owner, b.owner, "owner");
    assertEq(a.globalRestrict, b.globalRestrict, "globalRestrict");
    assertEq(a.totalSupply, b.totalSupply, "totalSupply");
    assertEq(a.totalAssets, b.totalAssets, "totalAssets");
    assertEq(a.lastCompoundTime, b.lastCompoundTime, "lastCompoundTime");
    assertEq(a.lastFeeTime, b.lastFeeTime, "lastFeeTime");
    assertEq(a.highWaterMark, b.highWaterMark, "highWaterMark");
    assertEq(a.deploymentDelay, b.deploymentDelay, "deploymentDelay");
    assertEq(a.yieldAPR, b.yieldAPR, "yieldAPR");
    assertEq(a.managementFeeRate, b.managementFeeRate, "managementFeeRate");
    assertEq(a.performanceFeeRate, b.performanceFeeRate, "performanceFeeRate");
    assertEq(a.withdrawalFeeRate, b.withdrawalFeeRate, "withdrawalFeeRate");
    assertEq(a.withdrawalGasFee, b.withdrawalGasFee, "withdrawalGasFee");
    assertEq(a.decimalsOffset, b.decimalsOffset, "decimalsOffset");
    assertEq(a.bufferAssets, b.bufferAssets, "bufferAssets");
    assertEq(a.requestCount, b.requestCount, "requestCount");
    assertEq(a.feeShares, b.feeShares, "feeShares");
    // The live implementation rounds the pre-fee price up, the new one down
    assertApproxEqAbs(a.pricePerShare, b.pricePerShare, 1, "pricePerShare");
    assertEq(a.assetsPerShare, b.assetsPerShare, "assetsPerShare");
    assertEq(a.feeRecipientShares, b.feeRecipientShares, "feeRecipientShares");
  }

  /// @dev A view the live implementation still has and the new one no longer does
  function _liveView(
    address vault,
    bytes memory call
  ) internal view returns (ILedgityDataProvider.WithdrawalRequestRead[] memory) {
    (bool ok, bytes memory data) = vault.staticcall(call);
    require(ok, "live view reverted");
    return abi.decode(data, (ILedgityDataProvider.WithdrawalRequestRead[]));
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

  function _unit(uint256 i) internal view returns (uint256) {
    return 10 ** IERC20Metadata(_vault(i).asset()).decimals();
  }

  /// @dev The liquidity manager adds liquidity to the buffer so the instant exits below can be paid
  function _topUpBuffer(uint256 i, uint256 assets) internal {
    LedgityYieldVault vault = _vault(i);
    if (detachBuffer && vault.hasBufferStrategy()) _detachBuffer(i);
    address manager = vault.liquidityManager();
    address asset = vault.asset();
    deal(asset, manager, IERC20(asset).balanceOf(manager) + assets);
    vm.startPrank(manager);
    IERC20(asset).approve(address(vault), assets);
    vault.depositToBuffer(assets);
    vm.stopPrank();
  }

  /// @dev The owner moves the vault off its Aave pool: the buffer comes back as idle assets
  function _detachBuffer(uint256 i) internal {
    LedgityYieldVault vault = _vault(i);
    IERC20 lToken = vault.lToken();
    IERC20 currentStakeToken = vault.stakeToken();
    uint256 stakeForFeeReduction = vault.stakeForFeeReduction();
    uint256 stakeForInstantWithdrawal = vault.stakeForInstantWithdrawal();
    uint256 bufferBefore = vault.getBufferAssets();
    address pool = address(vault.aaveLendingPool());
    address owner = vault.owner();

    vm.prank(owner);
    vault.updateVaultParams(
      lToken,
      currentStakeToken,
      stakeForFeeReduction,
      stakeForInstantWithdrawal,
      IAaveLendingPoolV3(address(0))
    );
    assertFalse(vault.hasBufferStrategy(), "pool detached");
    assertEq(vault.getBufferAssets(), bufferBefore, "buffer kept");
    bool upgraded = address(uint160(uint256(vm.load(address(vault), IMPLEMENTATION_SLOT)))) ==
      _implementation(i);
    if (upgraded)
      assertEq(IERC20(vault.asset()).allowance(address(vault), pool), 0, "allowance revoked");
  }

  function _deposit(
    uint256 i,
    address account,
    uint256 assets
  ) internal returns (uint256 shares) {
    LedgityYieldVault vault = _vault(i);
    if (detachBuffer && vault.hasBufferStrategy()) _detachBuffer(i);
    address asset = vault.asset();
    deal(asset, account, IERC20(asset).balanceOf(account) + assets);
    vm.startPrank(account);
    IERC20(asset).approve(address(vault), assets);
    shares = vault.deposit(assets, account);
    vm.stopPrank();
  }

  function _mockStake(address account, uint256 votingPower) internal {
    vm.mockCall(
      stakeToken,
      abi.encodeWithSelector(IERC20.balanceOf.selector, account),
      abi.encode(votingPower)
    );
  }

  function _requestIds(
    uint256 a,
    uint256 b
  ) internal pure returns (uint256[] memory ids) {
    ids = new uint256[](2);
    ids[0] = a;
    ids[1] = b;
  }

  // ======== TESTS ======== //

  function test_upgrade_onlyOwner() public {
    for (uint256 i; i < targets.length; i++) {
      vm.expectRevert(bytes("Ownable: caller is not the owner"));
      vm.prank(address(0xBAD));
      UUPSUpgradeable(targets[i].vault).upgradeTo(_implementation(i));
    }
  }

  function test_upgrade_preservesStateAndStorage() public {
    for (uint256 i; i < targets.length; i++) {
      address vault = targets[i].vault;
      Snapshot memory before = _snapshot(i);
      bytes32[] memory rawBefore = _rawStorage(vault);
      bytes memory liveView = abi.encodeWithSignature(
        "getWithdrawalRequests(bool,uint256)",
        false,
        uint256(0)
      );
      (bool liveOk, ) = vault.staticcall(liveView);
      assertTrue(liveOk, "the live implementation has the view");

      _upgrade(i);

      assertEq(
        address(uint160(uint256(vm.load(vault, IMPLEMENTATION_SLOT)))),
        _implementation(i),
        "implementation slot"
      );
      _assertSame(before, _snapshot(i));
      bytes32[] memory rawAfter = _rawStorage(vault);
      for (uint256 s; s < RAW_SLOTS; s++)
        assertEq(rawAfter[s], rawBefore[s], string.concat("slot ", vm.toString(s)));

      // The views now live in LedgityDataProvider
      (bool ok, ) = vault.staticcall(liveView);
      assertFalse(ok, "the removed view must not answer");
    }
  }

  function test_dataProvider_matchesLiveViews() public {
    for (uint256 i; i < targets.length; i++) {
      address vault = targets[i].vault;
      uint256 count = _vault(i).getWithdrawalRequestCount();
      ILedgityDataProvider.WithdrawalRequestRead[] memory all = _liveView(
        vault,
        abi.encodeWithSignature("getWithdrawalRequests(bool,uint256)", false, uint256(0))
      );
      ILedgityDataProvider.WithdrawalRequestRead[] memory pending = _liveView(
        vault,
        abi.encodeWithSignature("getWithdrawalRequests(bool,uint256)", true, uint256(0))
      );
      ILedgityDataProvider.WithdrawalRequestRead[] memory latest = _liveView(
        vault,
        abi.encodeWithSignature("getWithdrawalRequests(bool,uint256)", false, uint256(3))
      );
      ILedgityDataProvider.WithdrawalRequestRead[] memory ofUser;
      ILedgityDataProvider.WithdrawalRequestRead[] memory byIds;
      address requester;
      if (0 < count) {
        requester = all[all.length - 1].user;
        ofUser = _liveView(
          vault,
          abi.encodeWithSignature(
            "getUserWithdrawalRequests(address,bool,uint256)",
            requester,
            false,
            uint256(0)
          )
        );
        byIds = _liveView(
          vault,
          abi.encodeWithSignature(
            "getWithdrawalRequestsByIds(uint256[])",
            _requestIds(count - 1, 0)
          )
        );
      }

      _upgrade(i);

      _assertSameRequests(all, dataProvider.getWithdrawalRequests(vault, false, 0));
      _assertSameRequests(pending, dataProvider.getWithdrawalRequests(vault, true, 0));
      _assertSameRequests(latest, dataProvider.getWithdrawalRequests(vault, false, 3));
      if (0 < count) {
        _assertSameRequests(
          ofUser,
          dataProvider.getUserWithdrawalRequests(vault, requester, false, 0)
        );
        _assertSameRequests(
          byIds,
          dataProvider.getWithdrawalRequestsByIds(vault, _requestIds(count - 1, 0))
        );
      }
    }
  }

  function test_feeReductionSetter_keepsEverythingElse() public {
    for (uint256 i; i < targets.length; i++) {
      _upgrade(i);
      Snapshot memory before = _snapshot(i);

      _applyFeeReduction(i);

      Snapshot memory after_ = _snapshot(i);
      assertEq(after_.stakeForFeeReduction, STAKE_FOR_FEE_REDUCTION, "threshold set");
      assertEq(after_.stakeToken, stakeToken, "stake token set");
      // Everything else, the Aave buffer included, is untouched
      before.stakeForFeeReduction = STAKE_FOR_FEE_REDUCTION;
      before.stakeToken = stakeToken;
      _assertSame(before, after_);
    }
  }

  function test_highWaterMark_resetToThePriceAndKeptThere() public {
    for (uint256 i; i < targets.length; i++) {
      LedgityYieldVault vault = _vault(i);
      assertEq(vault.performanceFeeRate(), 0, "the live performance fee is zero");
      (, uint256 priceWhenBuilt) = vault.getFeeData();
      assertLt(priceWhenBuilt, 1e18 / 1000, "a 6-decimal price is far below 1e18");
      // The yield vaults carry the init artefact; lyREI was initialized at its price
      if (!targets[i].fixedTerm)
        assertEq(vault.highWaterMark(), 1e18, "the live mark is the init artefact");
      address feeRecipient = vault.feeRecipient();
      uint256 recipientBefore = vault.balanceOf(feeRecipient);

      _upgrade(i);
      _resetHighWaterMark(i, priceWhenBuilt);
      assertEq(vault.highWaterMark(), priceWhenBuilt, "mark reset");

      // The first harvest settles the mark on the price of the block, without taking a fee
      vm.warp(block.timestamp + 3 days);
      vault.harvestFees();
      (uint256 feeShares, uint256 price) = vault.getFeeData();
      uint256 mark = vault.highWaterMark();
      assertGe(mark, price, "mark at or above the price");
      assertLe(mark - price, 1, "mark within rounding of the price");
      assertEq(feeShares, 0, "no fee pending");
      assertEq(vault.balanceOf(feeRecipient), recipientBefore, "no fee taken by the reset");

      // Without a gain the mark does not move again
      vault.harvestFees();
      assertEq(vault.highWaterMark(), mark, "mark unchanged without a gain");
    }
  }

  function test_withdrawalFee_chargedBelowThresholdWaivedAbove() public {
    for (uint256 i; i < targets.length; i++) {
      LedgityYieldVault vault = _vault(i);
      _upgrade(i);
      _applyFeeReduction(i);
      _topUpBuffer(i, 1_000 * _unit(i));
      address feeRecipient = vault.feeRecipient();
      address asset = vault.asset();

      // Below the threshold: the live withdrawal fee rate applies on an instant exit
      uint256 shares = _deposit(i, user, 100 * _unit(i));
      uint256 expectedFee = shares.mulDiv(vault.withdrawalFeeRate(), RAY, Math.Rounding.Up);
      uint256 recipientBefore = vault.balanceOf(feeRecipient);
      uint256 assetsBefore = IERC20(asset).balanceOf(user);
      if (targets[i].fixedTerm) {
        // lyREI also gates instant exits on the stake: without it the queue is the only way out
        vm.expectRevert(LedgityYieldVault.InsufficientStakeForInstantWithdrawal.selector);
        vm.prank(user);
        vault.redeem(shares, user, user);
        _mockStake(user, vault.stakeForInstantWithdrawal());
      }
      vm.prank(user);
      vault.redeem(shares, user, user);
      assertEq(vault.balanceOf(feeRecipient) - recipientBefore, expectedFee, "fee charged");
      assertGt(IERC20(asset).balanceOf(user) - assetsBefore, 0, "assets received");
      assertEq(vault.balanceOf(user), 0, "shares burned");

      // At the threshold: no fee
      shares = _deposit(i, user, 100 * _unit(i));
      _mockStake(user, STAKE_FOR_FEE_REDUCTION);
      recipientBefore = vault.balanceOf(feeRecipient);
      vm.prank(user);
      vault.redeem(shares, user, user);
      assertEq(vault.balanceOf(feeRecipient), recipientBefore, "fee waived");
      vm.clearMockedCalls();
    }
  }

  function test_feeCheckpoint_advancesWithoutFees() public {
    for (uint256 i; i < targets.length; i++) {
      LedgityYieldVault vault = _vault(i);
      assertEq(vault.managementFeeRate(), 0, "the live management fee is zero");
      uint256 stale = vault.lastFeeTime();
      assertLt(stale, block.timestamp - 30 days, "the live checkpoint is stale");

      // Live implementation: a harvest without fees leaves the checkpoint where it is
      vault.harvestFees();
      assertEq(vault.lastFeeTime(), stale, "live checkpoint unchanged");

      _upgrade(i);
      vault.harvestFees();
      assertEq(vault.lastFeeTime(), block.timestamp, "checkpoint advanced");
    }
  }

  function test_processRequests_refusesDuplicateIds() public {
    for (uint256 i; i < targets.length; i++) {
      LedgityYieldVault vault = _vault(i);
      _upgrade(i);
      _topUpBuffer(i, 1_000 * _unit(i));

      uint256 shares = _deposit(i, user, 100 * _unit(i));
      uint256 gasFee = vault.withdrawalGasFee();
      vm.deal(user, gasFee);
      vm.prank(user);
      vault.requestWithdrawal{ value: gasFee }(shares);
      uint256 id = vault.getWithdrawalRequestCount() - 1;
      uint256 amount = dataProvider.getWithdrawalRequestsByIds(address(vault), _requestIds(id, id))[0].amount;
      address manager = vault.liquidityManager();

      vm.prank(manager);
      vm.expectRevert(LedgityYieldVault.RequestAlreadyProcessed.selector);
      vault.processRequests(_requestIds(id, id), 0);

      uint256[] memory ids = new uint256[](1);
      ids[0] = id;
      uint256 assetsBefore = IERC20(vault.asset()).balanceOf(user);
      vm.prank(manager);
      vault.processRequests(ids, 0);
      assertEq(IERC20(vault.asset()).balanceOf(user) - assetsBefore, amount, "paid once");
      assertTrue(dataProvider.getWithdrawalRequestsByIds(address(vault), ids)[0].processed);
    }
  }

  function test_blacklistedShares_canBeMovedByTheOwner() public {
    for (uint256 i; i < targets.length; i++) {
      LedgityYieldVault vault = _vault(i);
      address restricted = makeAddr(string.concat("restricted", vm.toString(i)));
      uint256 shares = _deposit(i, restricted, 100 * _unit(i));
      IGlobalAccessList accessList = vault.globalRestrict();
      address owner = vault.owner();
      vm.prank(owner);
      accessList.restrictAccount(restricted);
      assertTrue(accessList.isRestricted(restricted));

      // Live implementation: the owner cannot move the restricted holder's shares
      vm.expectRevert(AdministeredUpgradable.UserIsRestricted.selector);
      vm.prank(owner);
      vault.burnAndRemintBlacklistedShares(restricted, other);

      _upgrade(i);
      uint256 supply = vault.totalSupply();
      vm.prank(owner);
      vault.burnAndRemintBlacklistedShares(restricted, other);
      assertEq(vault.balanceOf(restricted), 0, "restricted balance cleared");
      assertEq(vault.balanceOf(other), shares, "shares reminted");
      assertEq(vault.totalSupply(), supply, "supply unchanged");
    }
  }

  /// @dev The whole bundle, then upgradeTo(live implementation) by the owner: every getter, every
  ///      raw slot and the moved views come back as they were, and the bundle can be replayed
  function test_rollback_restoresTheLiveImplementation() public {
    for (uint256 i; i < targets.length; i++) {
      address vault = targets[i].vault;
      address liveImplementation = address(
        uint160(uint256(vm.load(vault, IMPLEMENTATION_SLOT)))
      );
      bytes memory liveView = abi.encodeWithSignature(
        "getWithdrawalRequests(bool,uint256)",
        false,
        uint256(0)
      );
      ILedgityDataProvider.WithdrawalRequestRead[] memory before = _liveView(vault, liveView);

      _upgrade(i);
      (, uint256 price) = _vault(i).getFeeData();
      _resetHighWaterMark(i, price);
      Snapshot memory upgraded = _snapshot(i);
      bytes32[] memory rawUpgraded = _rawStorage(vault);

      address owner = _vault(i).owner();
      vm.prank(owner);
      UUPSUpgradeable(vault).upgradeTo(liveImplementation);

      assertEq(
        address(uint160(uint256(vm.load(vault, IMPLEMENTATION_SLOT)))),
        liveImplementation,
        "rolled back"
      );
      _assertSame(upgraded, _snapshot(i));
      bytes32[] memory rawRolledBack = _rawStorage(vault);
      for (uint256 s; s < RAW_SLOTS; s++)
        assertEq(rawRolledBack[s], rawUpgraded[s], string.concat("slot ", vm.toString(s)));
      // The live views answer again, equal to the provider; the requests are the ones from
      // before the bundle, only hasFeeReduction follows the new threshold
      ILedgityDataProvider.WithdrawalRequestRead[] memory liveNow = _liveView(vault, liveView);
      _assertSameRequests(liveNow, dataProvider.getWithdrawalRequests(vault, false, 0));
      assertEq(liveNow.length, before.length, "request count");
      for (uint256 r; r < before.length; r++) {
        assertEq(liveNow[r].requestId, before[r].requestId, "requestId");
        assertEq(liveNow[r].user, before[r].user, "user");
        assertEq(liveNow[r].amount, before[r].amount, "amount");
        assertEq(liveNow[r].timestamp, before[r].timestamp, "timestamp");
        assertEq(liveNow[r].processed, before[r].processed, "processed");
      }
      // The mark written by the bundle is plain storage, the live code reads it too
      assertEq(_vault(i).highWaterMark(), price);

      // Forward again: same state
      _upgrade(i);
      _assertSame(upgraded, _snapshot(i));
    }
  }

  /// @dev Neither the proxies nor the implementations can be (re)initialized, the
  ///      implementations refuse direct upgrades, and they answer the UUPS slot
  function test_proxyHygiene() public {
    ILedgityYieldVault.VaultParams memory params;
    IVaultLiquidityModule.VaultLiquidityInitParams memory liquidityParams;
    for (uint256 i; i < targets.length; i++) {
      address vault = targets[i].vault;
      address implementation = _implementation(i);
      _upgrade(i);

      vm.expectRevert(bytes("Initializable: contract is already initialized"));
      ILedgityYieldVault(vault).initialize(params, liquidityParams);

      vm.expectRevert(bytes("Initializable: contract is already initialized"));
      ILedgityYieldVault(implementation).initialize(params, liquidityParams);

      vm.expectRevert(bytes("Function must be called through delegatecall"));
      UUPSUpgradeable(implementation).upgradeTo(address(0xBAD));

      assertEq(
        UUPSUpgradeable(implementation).proxiableUUID(),
        IMPLEMENTATION_SLOT,
        "UUPS slot"
      );
      // Slot 0 is Initializable's _initialized: 255 means the constructor disabled it
      assertEq(
        uint256(vm.load(implementation, bytes32(uint256(0)))),
        255,
        "implementation initializers disabled"
      );
    }
  }

  function test_fixedTerm_migrateLTokenAlwaysReverts() public {
    for (uint256 i; i < targets.length; i++) {
      if (!targets[i].fixedTerm) continue;
      _upgrade(i);
      vm.expectRevert(FixedTermInvestmentVault.NoLTokenSet.selector);
      vm.prank(user);
      FixedTermInvestmentVault(targets[i].vault).migrateLToken(1);
    }
  }
}
