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
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

contract LedgityDataProvider_UnitTest is Test, Fixtures {
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

  // ======== WITHDRAWAL REQUEST DATA PROVIDER TESTS ======== //

  function test_getWithdrawalRequestCount_initial() public view {
    for (uint256 i = 0; i < vaults.length; i++) {
      assertEq(vaults[i].getWithdrawalRequestCount(), 0);
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

  function test_getWithdrawalRequestsByIds_returns_selected_requests()
    public
  {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create multiple withdrawal requests
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);
      vm.prank(testAccount2);
      vault.deposit(depositAmount, testAccount2);
      vm.prank(testAccount3);
      vault.deposit(depositAmount, testAccount3);

      uint256 shares1 = vault.balanceOf(testAccount1);
      uint256 shares2 = vault.balanceOf(testAccount2);
      uint256 shares3 = vault.balanceOf(testAccount3);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares1);
      vm.prank(testAccount2);
      vault.requestWithdrawal{ value: gasFee }(shares2);
      vm.prank(testAccount3);
      vault.requestWithdrawal{ value: gasFee }(shares3);

      // Get specific requests by IDs
      uint256[] memory requestIds = new uint256[](2);
      requestIds[0] = 0;
      requestIds[1] = 2;

      ILedgityDataProvider.WithdrawalRequestRead[]
        memory selectedRequests = vault.getWithdrawalRequestsByIds(
          requestIds
        );

      assertEq(selectedRequests.length, 2);
      assertEq(selectedRequests[0].requestId, 0);
      assertEq(selectedRequests[0].user, testAccount1);
      assertEq(selectedRequests[1].requestId, 2);
      assertEq(selectedRequests[1].user, testAccount3);
    }
  }

  function test_getUserWithdrawalRequests_filters_by_user() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create withdrawal requests from different users
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);
      vm.prank(testAccount2);
      vault.deposit(depositAmount, testAccount2);

      uint256 shares1 = vault.balanceOf(testAccount1);
      uint256 shares2 = vault.balanceOf(testAccount2);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares1);
      vm.prank(testAccount2);
      vault.requestWithdrawal{ value: gasFee }(shares2);

      // Get requests for testAccount1 only
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory user1Requests = vault.getUserWithdrawalRequests(
          testAccount1,
          false,
          0
        );

      assertEq(user1Requests.length, 1);
      assertEq(user1Requests[0].user, testAccount1);

      // Get requests for testAccount2 only
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory user2Requests = vault.getUserWithdrawalRequests(
          testAccount2,
          false,
          0
        );

      assertEq(user2Requests.length, 1);
      assertEq(user2Requests[0].user, testAccount2);
    }
  }

  function test_getWithdrawalRequests_pending_filter() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      // Create withdrawal requests
      vm.prank(testAccount1);
      vault.deposit(depositAmount, testAccount1);
      vm.prank(testAccount2);
      vault.deposit(depositAmount, testAccount2);

      uint256 shares1 = vault.balanceOf(testAccount1);
      uint256 shares2 = vault.balanceOf(testAccount2);
      uint256 gasFee = vault.withdrawalGasFee();

      vm.prank(testAccount1);
      vault.requestWithdrawal{ value: gasFee }(shares1);
      vm.prank(testAccount2);
      vault.requestWithdrawal{ value: gasFee }(shares2);

      // Process one request
      deal(address(config.asset), liquidityManager, depositAmount);
      vm.prank(liquidityManager);
      vault.depositToBuffer(depositAmount);

      uint256[] memory requestIds = new uint256[](1);
      requestIds[0] = 0;

      vm.prank(liquidityManager);
      vault.processRequests(requestIds, 0);

      // Get all requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory allRequests = vault.getWithdrawalRequests(false, 0);
      assertEq(allRequests.length, 2);

      // Get only pending requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory pendingRequests = vault.getWithdrawalRequests(true, 0);
      assertEq(pendingRequests.length, 1);
      assertEq(pendingRequests[0].requestId, 1);
      assertFalse(pendingRequests[0].processed);
    }
  }

  function test_getWithdrawalRequests_pagination() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      LedgityYieldVault vault = vaults[i];
      VaultConfig memory config = vaultConfigs[i];
      uint256 depositAmount = _getTestDepositAmount(config.asset);

      uint256 gasFee = vault.withdrawalGasFee();

      // Create multiple withdrawal requests
      for (uint256 j = 0; j < 5; j++) {
        address user = address(
          uint160(uint256(uint160(testAccount1)) + j)
        );
        deal(address(config.asset), user, depositAmount);
        deal(user, gasFee);

        vm.prank(user);
        config.asset.approve(address(vault), depositAmount);

        vm.prank(user);
        vault.deposit(depositAmount, user);

        uint256 shares = vault.balanceOf(user);

        vm.prank(user);
        vault.requestWithdrawal{ value: gasFee }(shares);
      }

      // Test pagination - get first 3 requests
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory firstPage = vault.getWithdrawalRequests(false, 3);
      assertEq(firstPage.length, 3);

      // Test getting all requests (no limit)
      ILedgityDataProvider.WithdrawalRequestRead[]
        memory allRequests = vault.getWithdrawalRequests(false, 0);
      assertEq(allRequests.length, 5);
    }
  }
}
