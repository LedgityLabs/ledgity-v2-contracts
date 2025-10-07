// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

contract VaultLiquidityModule_UnitTest is Test, Fixtures {
  // Test vault configurations
  struct VaultConfig {
    IERC20 asset;
    string assetName;
    uint256 decimals;
    bool hasAave;
    bool hasLToken;
  }

  VaultConfig[] public vaultConfigs;
  LedgityYieldVault[] public vaults;
  MockLToken[] public lTokens;

  uint256 public constant TEST_DEPOSIT_AMOUNT_USDC = 1000 * 1e6; // 1000 USDC (6 decimals)
  uint256 public constant TEST_DEPOSIT_AMOUNT_WETH = 1 * 1e18; // 1 WETH (18 decimals)

  function setUp() public {
    _setUp();
    _setupVaultConfigurations();
  }

  function _setupVaultConfigurations() internal {
    // Setup 4 vault configurations: USDC/WETH × with/without Aave
    vaultConfigs.push(
      VaultConfig({
        asset: usdc,
        assetName: "USDC",
        decimals: 6,
        hasAave: true,
        hasLToken: true
      })
    );

    vaultConfigs.push(
      VaultConfig({
        asset: usdc,
        assetName: "USDC",
        decimals: 6,
        hasAave: false,
        hasLToken: true
      })
    );

    vaultConfigs.push(
      VaultConfig({
        asset: weth,
        assetName: "WETH",
        decimals: 18,
        hasAave: true,
        hasLToken: false
      })
    );

    vaultConfigs.push(
      VaultConfig({
        asset: weth,
        assetName: "WETH",
        decimals: 18,
        hasAave: false,
        hasLToken: false
      })
    );

    // Create vaults and L-Tokens for each configuration
    for (uint256 i = 0; i < vaultConfigs.length; i++) {
      VaultConfig memory config = vaultConfigs[i];

      // Create L-Token for this asset
      MockLToken lToken;
      if (config.hasLToken) {
        lToken = _createLToken(config.asset);
        lTokens.push(lToken);
      }

      LedgityYieldVault vault = _createVaultWithConfig(
        config.asset,
        IERC20(address(lToken)),
        config.hasAave
      );
      vaults.push(vault);

      // Setup approvals for all test accounts
      _setupApprovalsForVault(vault, config.asset);
    }
  }

  function _getTestDepositAmount(
    IERC20 asset
  ) internal view returns (uint256) {
    // Return appropriate deposit amount based on asset decimals
    if (MockERC20(address(asset)).decimals() == 6) {
      return TEST_DEPOSIT_AMOUNT_USDC; // 1000 USDC
    } else {
      return TEST_DEPOSIT_AMOUNT_WETH; // 1 WETH
    }
  }

  // ======== BUFFER MANAGEMENT TESTS ======== //

  function test_getBufferAssets() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Deposit some assets to the vault
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 bufferAssets = vault.getBufferAssets();
      assertGt(bufferAssets, 0);
    }
  }

  function test_depositToBuffer_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      deal(address(config.asset), liquidityManager, depositAmount);

      vm.prank(liquidityManager);
      vault.depositToBuffer(depositAmount);

      assertGt(vault.getBufferAssets(), 0);
    }
  }

  function test_depositToBuffer_onlyLiquidityManager() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vm.expectRevert(
        LedgityYieldVault.OnlyLiquidityManager.selector
      );
      vault.depositToBuffer(depositAmount);
    }
  }

  function test_skimBuffer_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      deal(address(config.asset), liquidityManager, depositAmount);

      // First deposit to buffer
      vm.prank(liquidityManager);
      vault.depositToBuffer(depositAmount);

      uint256 initialBalance = config.asset.balanceOf(
        liquidityManager
      );

      vm.prank(liquidityManager);
      vault.skimBuffer(depositAmount / 2);

      assertGt(
        config.asset.balanceOf(liquidityManager),
        initialBalance
      );
    }
  }

  function test_skimBuffer_onlyLiquidityManager() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vm.expectRevert(
        LedgityYieldVault.OnlyLiquidityManager.selector
      );
      vault.skimBuffer(depositAmount / 2);
    }
  }

  // ======== HARVEST FEES TESTS ======== //

  function test_harvestFees_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Deposit to generate some activity
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      // Should not revert
      vault.harvestFees();
    }
  }

  // ======== VAULT LIQUIDITY MODULE ADMIN TESTS ======== //

  function test_updateAPR_updates_value() public {
    uint256 newAPR = (8 * RAY) / 100; // 8% APR

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      uint256 oldAPR = vault.yieldAPR();

      vm.prank(globalOwner.owner());
      vault.updateAPR(newAPR);

      assertEq(vault.yieldAPR(), newAPR);
      assertNotEq(vault.yieldAPR(), oldAPR);
    }
  }

  function test_updateFeeRates_updates_values() public {
    uint256 newManagementRate = (3 * RAY) / 1000; // 0.3%
    uint256 newPerformanceRate = (3 * RAY) / 100; // 3%
    uint256 newWithdrawalRate = (1 * RAY) / 1000; // 0.1%

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(globalOwner.owner());
      vault.updateFeeRates(
        newManagementRate,
        newPerformanceRate,
        newWithdrawalRate
      );

      assertEq(vault.managementFeeRate(), newManagementRate);
      assertEq(vault.performanceFeeRate(), newPerformanceRate);
      assertEq(vault.withdrawalFeeRate(), newWithdrawalRate);
    }
  }

  function test_setTotalAssets_resets_totalAssets_and_compound_time()
    public
  {
    uint256 newTotalAssets = 500 ether;

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      uint256 oldCompoundTime = vault.lastCompoundTime();

      vm.prank(globalOwner.owner());
      vault.setTotalAssets(newTotalAssets);

      assertEq(vault.totalAssets(), newTotalAssets);
      assertGe(vault.lastCompoundTime(), oldCompoundTime);
    }
  }

  function test_setAccountWithdrawalFee_affects_withdrawal_fee()
    public
  {
    uint256 customWithdrawalFee = (1 * RAY) / 100; // 1% custom fee

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Set custom withdrawal fee for testAccount1
      vm.prank(globalOwner.owner());
      vault.setAccountWithdrawalFee(
        testAccount1,
        customWithdrawalFee
      );

      assertEq(
        vault.accountWithdrawalFee(testAccount1),
        customWithdrawalFee
      );

      // Deposit and request withdrawal to test fee effect
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();
      uint256 initialFeeRecipientShares = vault.balanceOf(
        feeRecipient
      );

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      // Fee recipient should have received withdrawal fee shares
      assertGt(
        vault.balanceOf(feeRecipient),
        initialFeeRecipientShares
      );
    }
  }

  function test_updateDeploymentDelay_increases_maturity_impact()
    public
  {
    uint8 newDeploymentDelay = 7; // 7 days

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);
      uint8 decimalsOffset = vault.decimalsOffset();

      vm.prank(globalOwner.owner());
      vault.updateDeploymentDelay(newDeploymentDelay);

      assertEq(vault.deploymentDelay(), newDeploymentDelay);

      // First deposit should mint fewer shares due to maturity impact
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      // With deployment delay > 0, shares should be less than deposit amount
      // (when total supply is 0, normally shares = assets)
      uint256 shares = vault.balanceOf(testAccount1) /
        10 ** decimalsOffset;
      assertLt(shares, depositAmount);
    }
  }

  // ======== GETTER TESTS ======== //

  function test_RAY_constant_exposed() public view {
    for (uint256 i = 0; i < vaults.length; i++) {
      assertEq(vaults[i].RAY(), 1e27);
    }
  }

  function test_lastFeeTime_updates_on_harvestFees_with_time()
    public
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Deposit to generate some activity
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 oldLastFeeTime = vault.lastFeeTime();
      uint256 oldHighWaterMark = vault.highWaterMark();

      // Warp time forward
      vm.warp(block.timestamp + 1 days);

      vault.harvestFees();

      // lastFeeTime should be updated
      assertGe(vault.lastFeeTime(), oldLastFeeTime);
      // highWaterMark should be non-decreasing
      assertGe(vault.highWaterMark(), oldHighWaterMark);
    }
  }

  function test_aToken_is_set_only_when_hasBufferStrategy()
    public
    view
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];

      if (config.hasAave) {
        assertNotEq(address(vault.aToken()), address(0));
      } else {
        assertEq(address(vault.aToken()), address(0));
      }
    }
  }
}
