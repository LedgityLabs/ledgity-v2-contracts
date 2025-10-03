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
        stakeForFeeReduction: 0,
        stakeForInstantWithdrawal: 0,
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
          highWaterMark: 0,
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
        1000 ether,
        aaveLendingPool
      );

      assertEq(address(vault.lToken()), address(newLToken));
      assertEq(address(vault.stakeToken()), address(newStakeToken));
      assertEq(vault.stakeForFeeReduction(), 1000 ether);
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
        0,
        aaveLendingPool
      );
    }
  }

  // ======== MINT TESTS ======== //

  function test_mint_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Calculate shares to mint
      uint256 sharesToMint = vault.convertToShares(depositAmount);

      uint256 initialBalance = config.asset.balanceOf(testAccount1);
      uint256 initialTotalAssets = vault.totalAssets();

      vm.prank(testAccount1);
      vault.mint(sharesToMint, testAccount1);

      // Should have transferred assets from caller
      assertLt(config.asset.balanceOf(testAccount1), initialBalance);
      // Should have minted shares to receiver
      assertGt(vault.balanceOf(testAccount1), 0);
      // Should have increased total assets
      assertGt(vault.totalAssets(), initialTotalAssets);
    }
  }

  function test_mint_differentReceiver() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      uint256 sharesToMint = vault.convertToShares(depositAmount);

      vm.prank(testAccount1);
      vault.mint(sharesToMint, testAccount2);

      // Caller should have paid assets
      assertEq(vault.balanceOf(testAccount1), 0);
      // Receiver should have received shares
      assertGt(vault.balanceOf(testAccount2), 0);
    }
  }

  function test_mint_zeroShares_reverts() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert(LedgityYieldVault.ZeroAmount.selector);
      vault.mint(0, testAccount1);
    }
  }

  // ======== WITHDRAW TESTS ======== //

  function test_withdraw_success() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // First deposit
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 withdrawAmount = depositAmount / 10;
      uint256 initialBalance = config.asset.balanceOf(testAccount1);
      uint256 initialShares = vault.balanceOf(testAccount1);

      vm.prank(testAccount1);
      vault.withdraw(withdrawAmount, testAccount1, testAccount1);

      assertGt(config.asset.balanceOf(testAccount1), initialBalance);
      assertLt(vault.balanceOf(testAccount1), initialShares);
    }
  }

  // ======== PROCESS REQUESTS EDGE CASES ======== //

  function test_processRequests_insufficientLiquidity_reverts()
    public
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create a withdrawal request
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      uint256[] memory requestIds = new uint256[](1);
      requestIds[0] = 0;

      // Try to process without sufficient liquidity
      vm.prank(liquidityManager);
      vm.expectRevert(
        LedgityYieldVault.InsufficientLiquidity.selector
      );
      vault.processRequests(requestIds, 0);
    }
  }

  function test_processRequests_double_processing_reverts() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create a withdrawal request
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      // Add sufficient liquidity
      deal(address(config.asset), liquidityManager, depositAmount);
      vm.prank(liquidityManager);
      vault.depositToBuffer(depositAmount);

      uint256[] memory requestIds = new uint256[](1);
      requestIds[0] = 0;

      // Process once
      vm.prank(liquidityManager);
      vault.processRequests(requestIds, 0);

      // Try to process again - should revert
      vm.prank(liquidityManager);
      vm.expectRevert(
        LedgityYieldVault.RequestAlreadyProcessed.selector
      );
      vault.processRequests(requestIds, 0);
    }
  }

  function test_processRequests_with_added_liquidity_only() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create a withdrawal request
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares);

      // Get the request amount
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory requests = vault.getWithdrawalRequests(false, 0);
      uint256 requestAmount = requests[0].amount;

      // Provide exact liquidity needed via addedLiquidity parameter
      deal(address(config.asset), liquidityManager, requestAmount);

      uint256[] memory requestIds = new uint256[](1);
      requestIds[0] = 0;

      uint256 initialBalance = config.asset.balanceOf(testAccount1);

      vm.prank(liquidityManager);
      vault.processRequests(requestIds, requestAmount);

      assertGt(config.asset.balanceOf(testAccount1), initialBalance);
    }
  }

  // ======== BURN AND REMINT TESTS ======== //

  function test_burnAndRemintBlacklistedShares_onlyOwner_and_moves_shares()
    public
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Give testAccount1 some shares
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);

      uint256 shares = vault.balanceOf(testAccount1);
      uint256 initialAccount2Shares = vault.balanceOf(testAccount2);

      vm.prank(globalOwner.owner());
      vault.burnAndRemintBlacklistedShares(
        testAccount1,
        testAccount2
      );

      assertEq(vault.balanceOf(testAccount1), 0);
      assertEq(
        vault.balanceOf(testAccount2),
        initialAccount2Shares + shares
      );
    }
  }

  function test_burnAndRemintBlacklistedShares_onlyOwner() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];

      vm.prank(testAccount1);
      vm.expectRevert();
      vault.burnAndRemintBlacklistedShares(
        testAccount1,
        testAccount2
      );
    }
  }
}
