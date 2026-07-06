// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Simulated V2 — adds one new storage slot and new functions to verify
///      that upgrading to a new implementation is storage-safe.
contract LedgityYieldVaultV2Mock is LedgityYieldVault {
  uint256 public newFeatureFlag;

  function setNewFeatureFlag(uint256 value) external onlyOwner {
    newFeatureFlag = value;
  }

  function version() external pure returns (string memory) {
    return "2.0";
  }
}

contract LedgityYieldVault_UpgradeTest is Test, Fixtures {
  LedgityYieldVault vault;

  uint256 constant DEPOSIT = 1_000 * 1e6; // 1000 USDC (6 decimals)

  function setUp() public {
    _setUp();
    // Use no-Aave USDC vault to keep upgrade test self-contained
    vault = _createVaultWithConfig(usdc, IERC20(address(0)), false);
    _setupApprovalsForVault(vault, usdc);
  }

  function _upgradeToV2()
    internal
    returns (LedgityYieldVaultV2Mock vaultV2)
  {
    LedgityYieldVaultV2Mock newImpl = new LedgityYieldVaultV2Mock();
    // Caller is address(this) == deployer == globalOwner.owner() — authorized
    vault.upgradeTo(address(newImpl));
    vaultV2 = LedgityYieldVaultV2Mock(address(vault));
  }

  // ======== ACCESS CONTROL ======== //

  function test_upgrade_onlyOwner_reverts() public {
    LedgityYieldVaultV2Mock newImpl = new LedgityYieldVaultV2Mock();
    vm.prank(unauthorizedUser);
    vm.expectRevert("Ownable: caller is not the owner");
    vault.upgradeTo(address(newImpl));
  }

  // ======== REINITALIZATION GUARD ======== //

  function test_upgrade_blocksReinitialization() public {
    _upgradeToV2();

    ILedgityYieldVault.VaultParams memory params = ILedgityYieldVault
      .VaultParams({
        name: "Hacked",
        symbol: "HACK",
        asset: usdc,
        lToken: IERC20(address(0)),
        stakeToken: IERC20(address(0)),
        stakeForFeeReduction: 0,
        stakeForInstantWithdrawal: 0,
        globalOwner: address(globalOwner),
        globalPause: address(globalPause),
        globalAccessList: address(globalAccessList),
        liquidityManager: unauthorizedUser,
        feeRecipient: payable(unauthorizedUser),
        liquidityBufferRate: 0,
        aaveLendingPool: IAaveLendingPoolV3(address(0))
      });
    IVaultLiquidityModule.VaultLiquidityInitParams
      memory liqParams = IVaultLiquidityModule.VaultLiquidityInitParams({
        highWaterMark: 0,
        deploymentDelay: 0,
        initialAssetsPerShare: 0,
        yieldAPR: 0,
        managementFeeRate: 0,
        performanceFeeRate: 0,
        withdrawalFeeRate: 0,
        withdrawalGasFee: 0
      });

    vm.expectRevert(
      "Initializable: contract is already initialized"
    );
    vault.initialize(params, liqParams);
  }

  // ======== STATE PRESERVATION ======== //

  function test_upgrade_preservesConfigState() public {
    address preLiquidityManager = vault.liquidityManager();
    address preFeeRecipient = vault.feeRecipient();
    uint256 preLiquidityBufferRate = vault.liquidityBufferRate();
    uint256 preYieldAPR = vault.yieldAPR();
    uint256 preManagementFeeRate = vault.managementFeeRate();
    uint256 prePerformanceFeeRate = vault.performanceFeeRate();
    uint256 preWithdrawalFeeRate = vault.withdrawalFeeRate();
    bool preHasBufferStrategy = vault.hasBufferStrategy();
    uint8 preDeploymentDelay = vault.deploymentDelay();
    uint256 preHighWaterMark = vault.highWaterMark();

    _upgradeToV2();

    assertEq(
      vault.liquidityManager(),
      preLiquidityManager,
      "liquidityManager"
    );
    assertEq(
      vault.feeRecipient(),
      preFeeRecipient,
      "feeRecipient"
    );
    assertEq(
      vault.liquidityBufferRate(),
      preLiquidityBufferRate,
      "liquidityBufferRate"
    );
    assertEq(vault.yieldAPR(), preYieldAPR, "yieldAPR");
    assertEq(
      vault.managementFeeRate(),
      preManagementFeeRate,
      "managementFeeRate"
    );
    assertEq(
      vault.performanceFeeRate(),
      prePerformanceFeeRate,
      "performanceFeeRate"
    );
    assertEq(
      vault.withdrawalFeeRate(),
      preWithdrawalFeeRate,
      "withdrawalFeeRate"
    );
    assertEq(
      vault.hasBufferStrategy(),
      preHasBufferStrategy,
      "hasBufferStrategy"
    );
    assertEq(
      vault.deploymentDelay(),
      preDeploymentDelay,
      "deploymentDelay"
    );
    assertEq(
      vault.highWaterMark(),
      preHighWaterMark,
      "highWaterMark"
    );
  }

  function test_upgrade_preservesUserBalances() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);
    vm.prank(testAccount2);
    vault.deposit(DEPOSIT, testAccount2);

    uint256 preBal1 = vault.balanceOf(testAccount1);
    uint256 preBal2 = vault.balanceOf(testAccount2);
    uint256 preAssets = vault.totalAssets();
    uint256 preSupply = vault.totalSupply();

    _upgradeToV2();

    assertEq(
      vault.balanceOf(testAccount1),
      preBal1,
      "user1 share balance"
    );
    assertEq(
      vault.balanceOf(testAccount2),
      preBal2,
      "user2 share balance"
    );
    assertEq(vault.totalAssets(), preAssets, "totalAssets");
    assertEq(vault.totalSupply(), preSupply, "totalSupply");
  }

  function test_upgrade_preservesConversionRate() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    uint256 preToShares = vault.convertToShares(DEPOSIT);
    uint256 preToAssets = vault.convertToAssets(1e18);

    _upgradeToV2();

    assertEq(
      vault.convertToShares(DEPOSIT),
      preToShares,
      "convertToShares unchanged"
    );
    assertEq(
      vault.convertToAssets(1e18),
      preToAssets,
      "convertToAssets unchanged"
    );
  }

  function test_upgrade_preservesWithdrawalRequests() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: 0.001 ether }(shares);

    uint256 preCount = vault.getWithdrawalRequestCount();
    (
      address preUser,
      uint256 preAmount,
      uint256 preTimestamp,
      bool preProcessed
    ) = vault.withdrawalRequests(0);

    _upgradeToV2();

    assertEq(
      vault.getWithdrawalRequestCount(),
      preCount,
      "request count"
    );
    (
      address postUser,
      uint256 postAmount,
      uint256 postTimestamp,
      bool postProcessed
    ) = vault.withdrawalRequests(0);
    assertEq(postUser, preUser, "request user");
    assertEq(postAmount, preAmount, "request amount");
    assertEq(postTimestamp, preTimestamp, "request timestamp");
    assertEq(postProcessed, preProcessed, "request processed");
  }

  // ======== POST-UPGRADE OPERATIONS ======== //

  function test_upgrade_deposit_works() public {
    _upgradeToV2();

    uint256 preSupply = vault.totalSupply();

    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    assertGt(vault.balanceOf(testAccount1), 0, "shares minted");
    assertGt(vault.totalSupply(), preSupply, "supply increased");
  }

  function test_upgrade_requestWithdrawal_works() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    _upgradeToV2();

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 preCount = vault.getWithdrawalRequestCount();

    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: 0.001 ether }(shares);

    assertEq(
      vault.getWithdrawalRequestCount(),
      preCount + 1,
      "new request created"
    );
    assertEq(vault.balanceOf(testAccount1), 0, "shares burned");
  }

  function test_upgrade_processRequests_works() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    vm.prank(testAccount1);
    vault.requestWithdrawal{ value: 0.001 ether }(shares);

    (, uint256 requestedAmount, , ) = vault.withdrawalRequests(0);

    _upgradeToV2();

    // Fund LM with enough USDC to cover the request
    deal(address(usdc), liquidityManager, requestedAmount);

    uint256[] memory ids = new uint256[](1);
    ids[0] = 0;
    uint256 preUserBalance = usdc.balanceOf(testAccount1);

    vm.prank(liquidityManager);
    vault.processRequests(ids, requestedAmount);

    assertGt(
      usdc.balanceOf(testAccount1),
      preUserBalance,
      "user received USDC"
    );
    (, , , bool processed) = vault.withdrawalRequests(0);
    assertTrue(processed, "request marked processed");
  }

  // ======== V2 NEW FEATURES ======== //

  function test_upgrade_v2NewStorageSlot_startsAtZero() public {
    LedgityYieldVaultV2Mock vaultV2 = _upgradeToV2();
    assertEq(vaultV2.newFeatureFlag(), 0, "new slot initialized to zero");
  }

  function test_upgrade_v2NewStorageSlot_canBeSet() public {
    LedgityYieldVaultV2Mock vaultV2 = _upgradeToV2();
    vaultV2.setNewFeatureFlag(42);
    assertEq(vaultV2.newFeatureFlag(), 42, "new value stored");
  }

  function test_upgrade_v2NewStorageSlot_onlyOwner() public {
    LedgityYieldVaultV2Mock vaultV2 = _upgradeToV2();
    vm.prank(unauthorizedUser);
    vm.expectRevert("Ownable: caller is not the owner");
    vaultV2.setNewFeatureFlag(42);
  }

  function test_upgrade_v2Version() public {
    LedgityYieldVaultV2Mock vaultV2 = _upgradeToV2();
    assertEq(vaultV2.version(), "2.0", "version string");
  }

  function test_upgrade_v2WriteDoesNotCorruptV1State() public {
    vm.prank(testAccount1);
    vault.deposit(DEPOSIT, testAccount1);

    uint256 preBal = vault.balanceOf(testAccount1);
    uint256 preAssets = vault.totalAssets();

    LedgityYieldVaultV2Mock vaultV2 = _upgradeToV2();
    vaultV2.setNewFeatureFlag(99999);

    assertEq(
      vault.balanceOf(testAccount1),
      preBal,
      "user balance unaffected by V2 write"
    );
    assertEq(
      vault.totalAssets(),
      preAssets,
      "totalAssets unaffected by V2 write"
    );
    assertEq(vaultV2.newFeatureFlag(), 99999, "V2 state persisted");
  }
}
