// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test } from "foundry/lib/forge-std/src/Test.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { ScenarioComputations } from "tests/protocol-v2/helpers/ScenarioComputations.sol";
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
    uint256 amount,
    bool expectSuccess,
    bytes memory expectedRevertMsg
  ) internal returns (DepositResult memory result) {
    // Capture state before
    VaultState memory stateBefore = _captureStateBefore(
      vault,
      asset,
      user
    );

    if (expectSuccess) {
      // Execute deposit
      vm.startPrank(user);
      asset.approve(address(vault), amount);
      result.sharesMinted = vault.deposit(amount, user);
      vm.stopPrank();

      result.assetsDeposited = amount;

      // Capture state after
      VaultState memory stateAfter = _captureStateAfter(
        vault,
        asset,
        user
      );

      // Compute expected state
      VaultState
        memory expectedState = computeExpectedStateAfterDeposit(
          stateBefore,
          amount,
          vault
        );

      // Validate state transitions
      _validateDepositState(
        stateBefore,
        stateAfter,
        expectedState,
        result
      );
    } else {
      // Expect revert
      vm.startPrank(user);
      asset.approve(address(vault), amount);
      if (expectedRevertMsg.length > 0) {
        vm.expectRevert(expectedRevertMsg);
      } else {
        vm.expectRevert();
      }
      vault.deposit(amount, user);
      vm.stopPrank();
    }
  }

  /**
   * @notice Execute a time warp action
   * @param timeJump Amount of time to jump forward
   */
  function actionTimeWarp(uint256 timeJump) internal {
    vm.warp(block.timestamp + timeJump);
  }

  /**
   * @notice Execute a harvest fees action
   * @param vault The vault to harvest fees from
   */
  function actionHarvestFees(LedgityYieldVault vault) internal {
    VaultState memory stateBefore = _captureStateBeforeSimple(vault);

    vault.harvestFees();

    VaultState memory stateAfter = _captureStateAfterSimple(vault);

    // Validate fee time updated
    assertGe(
      stateAfter.lastFeeTime,
      stateBefore.lastFeeTime,
      "Fee time should not decrease"
    );
  }

  // ======== INTERNAL STATE CAPTURE ======== //

  function _captureStateBefore(
    LedgityYieldVault vault,
    IERC20 asset,
    address user
  ) internal view returns (VaultState memory state) {
    state.totalAssets = vault.totalAssets();
    state.totalSupply = vault.totalSupply();
    state.bufferAssets = vault.getBufferAssets();
    state.userAssetBalance = asset.balanceOf(user);
    state.userShareBalance = vault.balanceOf(user);
    state.liquidityManagerBalance = asset.balanceOf(
      vault.liquidityManager()
    );
    state.lastFeeTime = vault.lastFeeTime();
    state.lastCompoundTime = vault.lastCompoundTime();
    state.highWaterMark = vault.highWaterMark();
    state.sharePrice = _getSharePrice(vault);
  }

  function _captureStateAfter(
    LedgityYieldVault vault,
    IERC20 asset,
    address user
  ) internal view returns (VaultState memory state) {
    state.totalAssets = vault.totalAssets();
    state.totalSupply = vault.totalSupply();
    state.bufferAssets = vault.getBufferAssets();
    state.userAssetBalance = asset.balanceOf(user);
    state.userShareBalance = vault.balanceOf(user);
    state.liquidityManagerBalance = asset.balanceOf(
      vault.liquidityManager()
    );
    state.lastFeeTime = vault.lastFeeTime();
    state.lastCompoundTime = vault.lastCompoundTime();
    state.highWaterMark = vault.highWaterMark();
    state.sharePrice = _getSharePrice(vault);
  }

  function _captureStateBeforeSimple(
    LedgityYieldVault vault
  ) internal view returns (VaultState memory state) {
    state.totalAssets = vault.totalAssets();
    state.totalSupply = vault.totalSupply();
    state.lastFeeTime = vault.lastFeeTime();
    state.lastCompoundTime = vault.lastCompoundTime();
    state.highWaterMark = vault.highWaterMark();
  }

  function _captureStateAfterSimple(
    LedgityYieldVault vault
  ) internal view returns (VaultState memory state) {
    state.totalAssets = vault.totalAssets();
    state.totalSupply = vault.totalSupply();
    state.lastFeeTime = vault.lastFeeTime();
    state.lastCompoundTime = vault.lastCompoundTime();
    state.highWaterMark = vault.highWaterMark();
  }

  function _getSharePrice(
    LedgityYieldVault vault
  ) internal view returns (uint256) {
    uint256 totalSupply = vault.totalSupply();
    if (totalSupply == 0) return 1e18;
    return vault.convertToAssets(1e18);
  }

  // ======== INTERNAL VALIDATION ======== //

  /**
   * @notice Validate deposit state transitions
   */
  function _validateDepositState(
    VaultState memory stateBefore,
    VaultState memory stateAfter,
    VaultState memory expectedState,
    DepositResult memory result
  ) internal view {
    // User asset balance decreased
    assertEq(
      stateAfter.userAssetBalance,
      stateBefore.userAssetBalance - result.assetsDeposited,
      "User asset balance incorrect"
    );

    // User share balance increased
    assertEq(
      stateAfter.userShareBalance,
      stateBefore.userShareBalance + result.sharesMinted,
      "User share balance incorrect"
    );

    // Total supply increased
    assertEq(
      stateAfter.totalSupply,
      stateBefore.totalSupply + result.sharesMinted,
      "Total supply incorrect"
    );

    // Total assets increased (approximately, accounting for maturity impact)
    assertApproxEqRel(
      stateAfter.totalAssets,
      expectedState.totalAssets,
      0.001e18, // 0.1% tolerance
      "Total assets incorrect"
    );

    // Buffer or liquidity manager received assets
    uint256 totalAssetsReceived = (stateAfter.bufferAssets -
      stateBefore.bufferAssets) +
      (stateAfter.liquidityManagerBalance -
        stateBefore.liquidityManagerBalance);

    assertEq(
      totalAssetsReceived,
      result.assetsDeposited,
      "Assets not properly distributed"
    );
  }
}
