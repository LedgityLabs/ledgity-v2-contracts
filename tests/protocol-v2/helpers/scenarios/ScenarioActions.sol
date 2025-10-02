// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test } from "foundry/lib/forge-std/src/Test.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ScenarioComputations } from "tests/protocol-v2/helpers/scenarios/ScenarioComputations.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ScenarioActions
 * @notice Action handlers for scenario-based testing
 * @dev Each action captures state before/after and validates expected results
 */
contract ScenarioActions is Test, ScenarioComputations {
  // ======== STRUCTS ======== //

  struct DepositResult {
    uint256 sharesMinted;
    uint256 assetsDeposited;
    uint256 maturityImpact;
    uint256 netDeposit;
  }

  struct WithdrawResult {
    uint256 sharesBurned;
    uint256 assetsWithdrawn;
    uint256 withdrawalFee;
  }

  // ======== ACTIONS ======== //

  /**
   * @notice Execute a deposit action with state validation
   * @param vault The vault to deposit into
   * @param asset The underlying asset
   * @param user The user performing the deposit
   * @param amount The amount to deposit
   * @param expectSuccess Whether the action should succeed
   * @param expectedRevertMsg Expected revert message if action should fail
   * @return result deposit result data
   */
  function actionDeposit(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 amount,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal returns (DepositResult memory result) {
    if (expectSuccess) {
      result = _executeDepositSuccess(
        vault,
        asset,
        user,
        receiver,
        amount
      );
    } else {
      _executeDepositRevert(
        vault,
        asset,
        user,
        receiver,
        amount,
        expectedRevertMsg
      );
    }
  }

  function _executeDepositSuccess(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 amount
  ) private returns (DepositResult memory result) {
    VaultState memory vaultBefore = _captureVaultState(vault);
    AccountState memory accountBefore = _captureAccountState(
      vault,
      asset,
      user
    );

    vm.startPrank(user);
    asset.approve(address(vault), amount);
    result.sharesMinted = vault.deposit(amount, receiver);
    vm.stopPrank();

    result.assetsDeposited = amount;

    _validateDepositState(
      vault,
      asset,
      user,
      vaultBefore,
      accountBefore,
      amount,
      result.sharesMinted
    );
  }

  function _executeDepositRevert(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 amount,
    bytes memory expectedRevertMsg
  ) private {
    vm.startPrank(user);
    asset.approve(address(vault), amount);
    if (expectedRevertMsg.length > 0) {
      vm.expectRevert(expectedRevertMsg);
    } else {
      vm.expectRevert();
    }
    vault.deposit(amount, receiver);
    vm.stopPrank();
  }

  function _validateDepositState(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    VaultState memory vaultBefore,
    AccountState memory accountBefore,
    uint256 amount,
    uint256 sharesMinted
  ) private view {
    VaultState memory vaultAfter = _captureVaultState(vault);
    AccountState memory accountAfter = _captureAccountState(
      vault,
      asset,
      user
    );

    VaultState
      memory expectedVault = computeExpectedStateAfterDeposit(
        vaultBefore,
        amount,
        vault
      );
    AccountState
      memory expectedAccount = computeExpectedAccountsAfterDeposit(
        accountBefore,
        amount,
        sharesMinted,
        vaultBefore,
        vault
      );

    validateVaultState(vaultAfter, expectedVault, 0.001e18);
    validateAccountState(accountAfter, expectedAccount);
  }

  /**
   * @notice Execute a mint action with state validation
   */
  function actionMint(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 shares,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal returns (DepositResult memory result) {
    if (expectSuccess) {
      result = _executeMintSuccess(
        vault,
        asset,
        user,
        receiver,
        shares
      );
    } else {
      _executeMintRevert(
        vault,
        asset,
        user,
        receiver,
        shares,
        expectedRevertMsg
      );
    }
  }

  function _executeMintSuccess(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 shares
  ) private returns (DepositResult memory result) {
    VaultState memory vaultBefore = _captureVaultState(vault);
    AccountState memory accountBefore = _captureAccountState(
      vault,
      asset,
      user
    );

    vm.startPrank(user);
    uint256 assetsNeeded = vault.previewMint(shares);
    asset.approve(address(vault), assetsNeeded);
    result.assetsDeposited = vault.mint(shares, receiver);
    result.sharesMinted = shares;
    vm.stopPrank();

    _validateDepositState(
      vault,
      asset,
      user,
      vaultBefore,
      accountBefore,
      result.assetsDeposited,
      shares
    );
  }

  function _executeMintRevert(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    uint256 shares,
    bytes memory expectedRevertMsg
  ) private {
    vm.startPrank(user);
    uint256 assetsNeeded = vault.previewMint(shares);
    asset.approve(address(vault), assetsNeeded);
    if (expectedRevertMsg.length > 0) {
      vm.expectRevert(expectedRevertMsg);
    } else {
      vm.expectRevert();
    }
    vault.mint(shares, receiver);
    vm.stopPrank();
  }

  /**
   * @notice Execute a withdraw action with state validation
   */
  function actionWithdraw(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    address owner,
    uint256 assets,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal returns (WithdrawResult memory result) {
    if (expectSuccess) {
      result = _executeWithdrawSuccess(
        vault,
        asset,
        user,
        receiver,
        owner,
        assets
      );
    } else {
      _executeWithdrawRevert(
        vault,
        user,
        receiver,
        owner,
        assets,
        expectedRevertMsg
      );
    }
  }

  function _executeWithdrawSuccess(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    address owner,
    uint256 assets
  ) private returns (WithdrawResult memory result) {
    VaultState memory vaultBefore = _captureVaultState(vault);
    AccountState memory accountBefore = _captureAccountState(
      vault,
      asset,
      user
    );

    vm.startPrank(user);
    result.sharesBurned = vault.withdraw(assets, receiver, owner);
    result.assetsWithdrawn = assets;
    vm.stopPrank();

    _validateWithdrawState(
      vault,
      asset,
      user,
      vaultBefore,
      accountBefore,
      assets,
      result.sharesBurned
    );
  }

  function _executeWithdrawRevert(
    LedgityYieldVault vault,
    address user,
    address receiver,
    address owner,
    uint256 assets,
    bytes memory expectedRevertMsg
  ) private {
    vm.startPrank(user);
    if (expectedRevertMsg.length > 0) {
      vm.expectRevert(expectedRevertMsg);
    } else {
      vm.expectRevert();
    }
    vault.withdraw(assets, receiver, owner);
    vm.stopPrank();
  }

  function _validateWithdrawState(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    VaultState memory vaultBefore,
    AccountState memory accountBefore,
    uint256 assets,
    uint256 sharesBurned
  ) private view {
    VaultState memory vaultAfter = _captureVaultState(vault);
    AccountState memory accountAfter = _captureAccountState(
      vault,
      asset,
      user
    );

    VaultState
      memory expectedVault = computeExpectedStateAfterWithdraw(
        vaultBefore,
        assets,
        sharesBurned,
        vault
      );
    AccountState
      memory expectedAccount = computeExpectedAccountsAfterWithdraw(
        accountBefore,
        assets,
        sharesBurned,
        vaultBefore,
        vault
      );

    validateVaultState(vaultAfter, expectedVault, 0.001e18);
    validateAccountState(accountAfter, expectedAccount);
  }

  /**
   * @notice Execute a redeem action with state validation
   */
  function actionRedeem(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    address owner,
    uint256 shares,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal returns (WithdrawResult memory result) {
    if (expectSuccess) {
      result = _executeRedeemSuccess(
        vault,
        asset,
        user,
        receiver,
        owner,
        shares
      );
    } else {
      _executeRedeemRevert(
        vault,
        user,
        receiver,
        owner,
        shares,
        expectedRevertMsg
      );
    }
  }

  function _executeRedeemSuccess(
    LedgityYieldVault vault,
    IERC20 asset,
    address user,
    address receiver,
    address owner,
    uint256 shares
  ) private returns (WithdrawResult memory result) {
    VaultState memory vaultBefore = _captureVaultState(vault);
    AccountState memory accountBefore = _captureAccountState(
      vault,
      asset,
      user
    );

    vm.startPrank(user);
    result.assetsWithdrawn = vault.redeem(shares, receiver, owner);
    result.sharesBurned = shares;
    vm.stopPrank();

    _validateWithdrawState(
      vault,
      asset,
      user,
      vaultBefore,
      accountBefore,
      result.assetsWithdrawn,
      shares
    );
  }

  function _executeRedeemRevert(
    LedgityYieldVault vault,
    address user,
    address receiver,
    address owner,
    uint256 shares,
    bytes memory expectedRevertMsg
  ) private {
    vm.startPrank(user);
    if (expectedRevertMsg.length > 0) {
      vm.expectRevert(expectedRevertMsg);
    } else {
      vm.expectRevert();
    }
    vault.redeem(shares, receiver, owner);
    vm.stopPrank();
  }

  /**
   * @notice Execute a request withdrawal action
   */
  function actionRequestWithdrawal(
    LedgityYieldVault vault,
    address user,
    uint256 shares,
    uint256 gasFee,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    VaultState memory vaultBefore = _captureVaultState(vault);

    if (expectSuccess) {
      vm.startPrank(user);
      vm.deal(user, gasFee);
      vault.requestWithdrawal{ value: gasFee }(shares);
      vm.stopPrank();

      VaultState memory vaultAfter = _captureVaultState(vault);

      assertLt(
        vaultAfter.totalSupply,
        vaultBefore.totalSupply,
        "Total supply should decrease after request"
      );
    } else {
      vm.startPrank(user);
      vm.deal(user, gasFee);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.requestWithdrawal{ value: gasFee }(shares);
      vm.stopPrank();
    }
  }

  /**
   * @notice Execute a process requests action
   */
  function actionProcessRequests(
    LedgityYieldVault vault,
    IERC20 asset,
    address liquidityManager,
    uint256[] memory requestIds,
    uint256 addAssets,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.startPrank(liquidityManager);
      if (addAssets > 0) {
        asset.approve(address(vault), addAssets);
      }
      vault.processRequests(requestIds, addAssets);
      vm.stopPrank();
    } else {
      vm.startPrank(liquidityManager);
      if (addAssets > 0) {
        asset.approve(address(vault), addAssets);
      }
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.processRequests(requestIds, addAssets);
      vm.stopPrank();
    }
  }

  /**
   * @notice Execute a deposit to buffer action
   */
  function actionDepositToBuffer(
    LedgityYieldVault vault,
    IERC20 asset,
    address liquidityManager,
    uint256 amount,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.startPrank(liquidityManager);
      asset.approve(address(vault), amount);
      vault.depositToBuffer(amount);
      vm.stopPrank();
    } else {
      vm.startPrank(liquidityManager);
      asset.approve(address(vault), amount);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.depositToBuffer(amount);
      vm.stopPrank();
    }
  }

  /**
   * @notice Execute a skim buffer action
   */
  function actionSkimBuffer(
    LedgityYieldVault vault,
    address liquidityManager,
    uint256 amount,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.prank(liquidityManager);
      vault.skimBuffer(amount);
    } else {
      vm.prank(liquidityManager);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.skimBuffer(amount);
    }
  }

  /**
   * @notice Execute a harvest fees action
   */
  function actionHarvestFees(
    LedgityYieldVault vault,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    VaultState memory vaultBefore = _captureVaultState(vault);

    if (expectSuccess) {
      vault.harvestFees();

      VaultState memory vaultAfter = _captureVaultState(vault);

      assertGe(
        vaultAfter.lastFeeTime,
        vaultBefore.lastFeeTime,
        "Fee time should not decrease"
      );
    } else {
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.harvestFees();
    }
  }

  /**
   * @notice Execute a migrate LToken action
   */
  function actionMigrateLToken(
    LedgityYieldVault vault,
    address user,
    uint256 amount,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.startPrank(user);
      IERC20(address(vault.lToken())).approve(address(vault), amount);
      vault.migrateLToken(amount);
      vm.stopPrank();
    } else {
      vm.startPrank(user);
      IERC20(address(vault.lToken())).approve(address(vault), amount);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.migrateLToken(amount);
      vm.stopPrank();
    }
  }

  /**
   * @notice Execute an update APR action
   */
  function actionUpdateAPR(
    LedgityYieldVault vault,
    address owner,
    uint256 newAPR,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.prank(owner);
      vault.updateAPR(newAPR);
    } else {
      vm.prank(owner);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.updateAPR(newAPR);
    }
  }

  /**
   * @notice Execute an update fees action
   */
  function actionUpdateFees(
    LedgityYieldVault vault,
    address owner,
    uint256 managementFee,
    uint256 performanceFee,
    uint256 withdrawalFee,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.prank(owner);
      vault.updateFeeRates(
        managementFee,
        performanceFee,
        withdrawalFee
      );
    } else {
      vm.prank(owner);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.updateFeeRates(
        managementFee,
        performanceFee,
        withdrawalFee
      );
    }
  }

  /**
   * @notice Execute a set total assets action
   */
  function actionSetTotalAssets(
    LedgityYieldVault vault,
    address owner,
    uint256 newTotalAssets,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal {
    if (expectSuccess) {
      vm.prank(owner);
      vault.setTotalAssets(newTotalAssets);
    } else {
      vm.prank(owner);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.setTotalAssets(newTotalAssets);
    }
  }

  /**
   * @notice Execute a time warp action
   * @param timeJump Amount of time to jump forward
   */
  function actionTimeWarp(uint256 timeJump) internal {
    vm.warp(block.timestamp + timeJump);
  }

  // ======== INTERNAL STATE CAPTURE ======== //

  function _captureVaultState(
    LedgityYieldVault vault
  ) internal view returns (VaultState memory state) {
    state.totalAssets = vault.totalAssets();
    state.totalSupply = vault.totalSupply();
    state.bufferAssets = vault.getBufferAssets();
    state.lastFeeTime = vault.lastFeeTime();
    state.lastCompoundTime = vault.lastCompoundTime();
    state.highWaterMark = vault.highWaterMark();
    state.sharePrice = _getSharePrice(vault);
  }

  function _captureAccountState(
    LedgityYieldVault vault,
    IERC20 asset,
    address user
  ) internal view returns (AccountState memory state) {
    state.userAssetBalance = asset.balanceOf(user);
    state.userShareBalance = vault.balanceOf(user);
    state.liquidityManagerAssetBalance = asset.balanceOf(
      vault.liquidityManager()
    );
    state.feeRecipientShareBalance = vault.balanceOf(
      vault.feeRecipient()
    );
  }

  function _getSharePrice(
    LedgityYieldVault vault
  ) internal view returns (uint256) {
    uint256 totalSupply = vault.totalSupply();
    if (totalSupply == 0) return 1e18;
    return vault.convertToAssets(1e18);
  }
}
