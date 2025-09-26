// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

contract LedgityYieldVault_UnitTest is Test, Fixtures {
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
  uint256 public constant TEST_DEPOSIT_AMOUNT = 1000 ether; // Legacy constant for compatibility
  uint256 public constant TEST_SHARES_AMOUNT = 500 * 1e18; // Always 18 decimals for shares

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

      // Create vault - modify _createVault to handle Aave configuration
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

  function _createVaultWithConfig(
    IERC20 asset_,
    IERC20 lToken_,
    bool hasAave_
  ) internal returns (LedgityYieldVault) {
    LedgityYieldVault yieldVaultImpl = new LedgityYieldVault();
    ERC1967Proxy yieldVaultProxy = new ERC1967Proxy(
      address(yieldVaultImpl),
      ""
    );
    LedgityYieldVault yieldVault = LedgityYieldVault(
      address(yieldVaultProxy)
    );

    string memory name = string.concat(
      "Test ",
      MockERC20(address(asset_)).name(),
      hasAave_ ? " (Aave)" : " (No Aave)"
    );
    string memory symbol = string.concat(
      "t",
      MockERC20(address(asset_)).symbol(),
      hasAave_ ? "A" : "N"
    );

    ILedgityYieldVault.VaultParams memory vaultParams = ILedgityYieldVault
      .VaultParams({
        name: name,
        symbol: symbol,
        asset: asset_,
        lToken: lToken_,
        stakeToken: ldyToken,
        stakeBalanceForFeeReduction: 1000 * 1e18,
        globalOwner: address(globalOwner),
        globalPause: address(globalPause),
        globalAccessList: address(globalAccessList),
        liquidityManager: liquidityManager,
        feeRecipient: payable(feeRecipient),
        liquidityBufferRate: (10 * RAY) / 100, // 10%
        aaveLendingPool: hasAave_
          ? aaveLendingPool
          : IAaveLendingPoolV3(address(0))
      });

    IVaultLiquidityModule.VaultLiquidityInitParams
      memory vaultLiquidityInitParams = IVaultLiquidityModule
        .VaultLiquidityInitParams({
          highWaterMark: RAY,
          deploymentDelay: 1,
          yieldAPR: (5 * RAY) / 100, // 5% APR
          managementFeeRate: (2 * RAY) / 1000, // 0.2%
          performanceFeeRate: (2 * RAY) / 100, // 2%
          withdrawalFeeRate: (5 * RAY) / 10000, // 0.05%
          withdrawalGasFee: 0.001 ether
        });

    yieldVault.initialize(vaultParams, vaultLiquidityInitParams);

    return yieldVault;
  }

  function _setupApprovalsForVault(
    LedgityYieldVault vault,
    IERC20 asset
  ) internal {
    address[] memory accounts = new address[](4);
    accounts[0] = testAccount1;
    accounts[1] = testAccount2;
    accounts[2] = testAccount3;
    accounts[3] = liquidityManager;

    for (uint256 i = 0; i < accounts.length; i++) {
      vm.prank(accounts[i]);
      asset.approve(address(vault), type(uint256).max);
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

  // ======== INITIALIZATION TESTS ======== //

  function test_initialization() public view {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];

      // Test basic initialization
      assertEq(address(vault.asset()), address(config.asset));
      assertEq(vault.liquidityManager(), liquidityManager);
      assertEq(vault.feeRecipient(), feeRecipient);
      assertEq(vault.liquidityBufferRate(), (10 * RAY) / 100);
      assertEq(vault.decimals(), 18);
      assertEq(vault.totalSupply(), 0);
      assertEq(vault.totalAssets(), 0);

      // Test Aave configuration
      if (config.hasAave) {
        assertTrue(vault.hasBufferStrategy());
        assertEq(
          address(vault.aaveLendingPool()),
          address(aaveLendingPool)
        );
      } else {
        assertFalse(vault.hasBufferStrategy());
        assertEq(address(vault.aaveLendingPool()), address(0));
      }
    }
  }

  function test_initialization_zeroAddress_reverts() public {
    ILedgityYieldVault.VaultParams memory invalidParams = ILedgityYieldVault
      .VaultParams({
        name: "Test Vault",
        symbol: "TV",
        asset: IERC20(address(0)), // Invalid zero address
        lToken: IERC20(address(0)),
        stakeToken: IERC20(address(0)),
        stakeBalanceForFeeReduction: 0,
        globalOwner: address(globalOwner),
        globalPause: address(globalPause),
        globalAccessList: address(globalAccessList),
        liquidityManager: liquidityManager,
        feeRecipient: payable(feeRecipient),
        liquidityBufferRate: 10000,
        aaveLendingPool: aaveLendingPool
      });

    IVaultLiquidityModule.VaultLiquidityInitParams
      memory liquidityParams = IVaultLiquidityModule
        .VaultLiquidityInitParams({
          highWaterMark: RAY,
          deploymentDelay: 1,
          yieldAPR: 5 * RAY,
          managementFeeRate: 200,
          performanceFeeRate: 2000,
          withdrawalFeeRate: 50,
          withdrawalGasFee: 0.001 ether
        });

    LedgityYieldVault newImpl = new LedgityYieldVault();
    bytes memory initData = abi.encodeWithSelector(
      LedgityYieldVault.initialize.selector,
      invalidParams,
      liquidityParams
    );

    vm.expectRevert(LedgityYieldVault.ZeroAddress.selector);
    new ERC1967Proxy(address(newImpl), initData);
  }

  // ======== VIEW FUNCTION TESTS ======== //

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

  function test_getWithdrawalRequestCount_initial() public view {
    for (uint256 i = 0; i < vaults.length; i++) {
      assertEq(vaults[i].getWithdrawalRequestCount(), 0);
    }
  }

  function test_owner_returnsGlobalOwner() public view {
    for (uint256 i = 0; i < vaults.length; i++) {
      assertEq(vaults[i].owner(), globalOwner.owner());
    }
  }

  // ======== DEPOSIT TESTS ======== //

  function test_deposit_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      uint256 initialBalance = config.asset.balanceOf(testAccount1);
      uint256 initialTotalAssets = vault.totalAssets();

      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      assertEq(
        config.asset.balanceOf(testAccount1),
        initialBalance - depositAmount
      );
      assertGt(vault.balanceOf(testAccount1), 0);
      assertGt(vault.totalAssets(), initialTotalAssets);
      assertGt(vault.totalSupply(), 0);
    }
  }

  function test_deposit_zeroAmount_reverts() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      vm.prank(testAccount1);
      vm.expectRevert(LedgityYieldVault.ZeroAmount.selector);
      vaults[i].deposit(0, testAccount1);
    }
  }

  function test_deposit_differentReceiver() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount2);

      assertEq(vault.balanceOf(testAccount1), 0);
      assertGt(vault.balanceOf(testAccount2), 0);
    }
  }

  // ======== WITHDRAWAL REQUEST TESTS ======== //

  function test_requestWithdrawal_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // First deposit
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      assertEq(vault.balanceOf(testAccount1), 0);
      assertEq(vault.getWithdrawalRequestCount(), 1);
    }
  }

  function test_requestWithdrawal_insufficientGasFee_reverts()
    public
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);

      vm.prank(testAccount1);
      vm.expectRevert(
        LedgityYieldVault.MissingWithdrawalRequestFee.selector
      );
      vault.requestWithdrawal{ value: 0 }(shares);
    }
  }

  function test_requestWithdrawal_zeroShares_reverts() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vm.expectRevert(LedgityYieldVault.ZeroAmount.selector);
      vault.requestWithdrawal{ value: gasFee }(0);
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

  // ======== ADMIN FUNCTION TESTS ======== //

  function test_updateVaultManagers_success() public {
    address newLiquidityManager = address(0x123);
    address payable newFeeRecipient = payable(address(0x456));

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(globalOwner.owner());
      vault.updateVaultManagers(newLiquidityManager, newFeeRecipient);

      assertEq(vault.liquidityManager(), newLiquidityManager);
      assertEq(vault.feeRecipient(), newFeeRecipient);
    }
  }

  function test_updateVaultManagers_zeroAddress_reverts() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(globalOwner.owner());
      vm.expectRevert(LedgityYieldVault.ZeroAddress.selector);
      vault.updateVaultManagers(address(0), payable(address(0x456)));
    }
  }

  function test_updateVaultManagers_onlyOwner() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.updateVaultManagers(
        address(0x123),
        payable(address(0x456))
      );
    }
  }

  function test_updateBufferRate_success() public {
    uint256 newRate = 15000; // 15%

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(globalOwner.owner());
      vault.updateBufferRate(newRate);

      assertEq(vault.liquidityBufferRate(), newRate);
    }
  }

  function test_updateBufferRate_onlyOwner() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.updateBufferRate(15000);
    }
  }

  // ======== BUFFER MANAGEMENT TESTS ======== //

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

  // ======== PROCESS REQUESTS TESTS ======== //

  function test_processRequests_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create a withdrawal request first
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      deal(address(config.asset), liquidityManager, depositAmount);

      // Add liquidity to buffer for processing
      vm.prank(liquidityManager);
      vault.depositToBuffer(depositAmount);

      uint256[] memory requestIds = new uint256[](1);
      requestIds[0] = 0;

      uint256 initialBalance = config.asset.balanceOf(testAccount1);

      vm.prank(liquidityManager);
      vault.processRequests(requestIds, 0);

      assertGt(config.asset.balanceOf(testAccount1), initialBalance);
    }
  }

  function test_processRequests_onlyLiquidityManager() public {
    uint256[] memory requestIds = new uint256[](0);

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert(
        LedgityYieldVault.OnlyLiquidityManager.selector
      );
      vault.processRequests(requestIds, 0);
    }
  }

  // ======== ACCESS CONTROL TESTS ======== //

  function test_whenPaused_deposit_reverts() public {
    vm.prank(globalOwner.owner());
    globalPause.pause();

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.deposit(depositAmount, testAccount1);
    }
  }

  function test_whenPaused_withdraw_reverts() public {
    // First deposit when not paused
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);
    }

    // Then pause
    vm.prank(globalOwner.owner());
    globalPause.pause();

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      uint256 shares = vault.balanceOf(testAccount1);

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.redeem(shares, testAccount1, testAccount1);
    }
  }

  // ======== CONVERSION TESTS ======== //

  function test_convertToShares_convertToAssets_consistency() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Deposit some assets first to establish a rate
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 testAssets = depositAmount;
      uint256 shares = vault.convertToShares(testAssets);
      uint256 backToAssets = vault.convertToAssets(shares);

      // Should be approximately equal (allowing for rounding)
      assertApproxEqRel(testAssets, backToAssets, 0.01e18); // 1% tolerance
    }
  }

  // ======== L-TOKEN MIGRATION TESTS ======== //

  function test_migrateLToken_noLTokenSet_reverts() public {
    // Test with vaults that have no L-Token set (our default setup)
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      if (!config.hasLToken) {
        vm.prank(testAccount1);
        vm.expectRevert(LedgityYieldVault.NoLTokenSet.selector);
        vault.migrateLToken(depositAmount);
      }
    }
  }

  function test_migrateLToken_zeroAmount_reverts() public {
    // Test with vaults that have L-Token support
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      if (address(vault.lToken()) == address(0)) continue;

      MockLToken lToken = lTokens[i];

      // Approve L-Token for migration
      vm.prank(testAccount1);
      lToken.approve(address(vault), type(uint256).max);

      vm.prank(testAccount1);
      vm.expectRevert(LedgityYieldVault.ZeroAmount.selector);
      vault.migrateLToken(0);
    }
  }

  function test_migrateLToken_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      if (address(vault.lToken()) == address(0)) continue;

      MockLToken lToken = lTokens[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 migrationAmount = _getTestDepositAmount(config.asset);

      // Setup L-Token balance and approval
      lToken.mint(testAccount1, migrationAmount);
      vm.prank(testAccount1);
      lToken.approve(address(vault), type(uint256).max);

      uint256 initialLTokenBalance = lToken.balanceOf(testAccount1);
      uint256 initialVaultShares = vault.balanceOf(testAccount1);

      vm.prank(testAccount1);
      uint256 shares = vault.migrateLToken(migrationAmount);

      assertEq(
        lToken.balanceOf(testAccount1),
        initialLTokenBalance - migrationAmount
      );
      assertEq(
        vault.balanceOf(testAccount1),
        initialVaultShares + shares
      );
      assertGt(shares, 0);
      assertGt(vault.totalAssets(), 0);
      assertGt(vault.totalSupply(), 0);
    }
  }

  // ======== EDGE CASE TESTS ======== //

  function test_multipleDepositsAndWithdrawals() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Multiple users deposit
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      vm.prank(testAccount2);
      vault.deposit(depositAmount * 2, testAccount2);

      vm.prank(testAccount3);
      vault.deposit(depositAmount / 2, testAccount3);

      // Check balances
      assertGt(vault.balanceOf(testAccount1), 0);
      assertGt(
        vault.balanceOf(testAccount2),
        vault.balanceOf(testAccount1)
      );
      assertLt(
        vault.balanceOf(testAccount3),
        vault.balanceOf(testAccount1)
      );

      // Partial withdrawal
      uint256 shares1 = vault.balanceOf(testAccount1) / 4;
      vm.prank(testAccount1);
      vault.redeem(shares1, testAccount1, testAccount1);

      assertGt(vault.balanceOf(testAccount1), 0);
      assertGt(vault.totalSupply(), 0);
    }
  }

  function test_depositWithZeroTotalSupply() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // First deposit when total supply is 0
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      // Should mint shares at 1:1 ratio initially
      assertGt(vault.balanceOf(testAccount1), 0);
      assertEq(vault.totalSupply(), vault.balanceOf(testAccount1));
    }
  }

  function test_getWithdrawalRequests_functionality() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create some withdrawal requests
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      // Test getting all requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory requests = vault.getWithdrawalRequests(false, 0);
      assertEq(requests.length, 1);
      assertEq(requests[0].user, testAccount1);
      assertFalse(requests[0].processed);

      // Test getting only pending requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory pendingRequests = vault.getWithdrawalRequests(true, 0);
      assertEq(pendingRequests.length, 1);

      // Test getting user-specific requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory userRequests = vault.getUserWithdrawalRequests(
          testAccount1,
          false,
          0
        );
      assertEq(userRequests.length, 1);
      assertEq(userRequests[0].user, testAccount1);
    }
  }

  function test_updateVaultParams_success() public {
    MockERC20 newLToken = new MockERC20("New L-Token", "NLT", 18);
    MockERC20 newStakeToken = new MockERC20(
      "New Stake Token",
      "NST",
      18
    );

    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(globalOwner.owner());
      vault.updateVaultParams(
        IERC20(address(newLToken)),
        IERC20(address(newStakeToken)),
        1000 ether,
        aaveLendingPool
      );

      assertEq(address(vault.lToken()), address(newLToken));
      assertEq(address(vault.stakeToken()), address(newStakeToken));
      assertEq(vault.stakeBalanceForFeeReduction(), 1000 ether);
    }
  }

  function test_updateVaultParams_onlyOwner() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.updateVaultParams(
        IERC20(address(0)),
        IERC20(address(0)),
        0,
        aaveLendingPool
      );
    }
  }
}
