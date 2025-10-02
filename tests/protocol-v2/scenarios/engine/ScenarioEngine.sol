// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
import { ScenarioActions } from "tests/protocol-v2/helpers/scenarios/ScenarioActions.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ScenarioEngine
 * @notice Base contract for executing scenario-based tests from struct arrays
 * @dev Provides action types and execution logic for deterministic test scenarios
 */
abstract contract ScenarioEngine is Test, Fixtures, ScenarioActions {
  // ======== ENUMS ======== //

  enum ActionType {
    Deposit,
    Mint,
    Withdraw,
    Redeem,
    RequestWithdrawal,
    ProcessRequests,
    DepositToBuffer,
    SkimBuffer,
    HarvestFees,
    MigrateLToken,
    TimeWarp,
    UpdateAPR,
    UpdateFees,
    SetTotalAssets
  }

  enum ExpectedOutcome {
    Success,
    Revert
  }

  // ======== STRUCTS ======== //

  struct ScenarioAction {
    ActionType actionType;
    address actor;
    uint256 timeWarp;
    ExpectedOutcome expected;
    bytes revertMessage;
    bytes args;
    uint8 vaultIndex;
  }

  struct VaultConfig {
    LedgityYieldVault vault;
    IERC20 asset;
    string name;
  }

  // ======== STATE ======== //

  LedgityYieldVault internal vault;
  IERC20 internal asset;
  uint256 internal scenarioStartTime;

  VaultConfig[] internal vaults;
  bool internal multiVaultMode;

  // ======== ENGINE FUNCTIONS ======== //

  /**
   * @notice Execute a scenario from an array of actions
   * @param actions Array of actions to execute sequentially
   * @param scenarioName Name of the scenario for logging
   */
  function executeScenario(
    ScenarioAction[] memory actions,
    string memory scenarioName
  ) internal {
    scenarioStartTime = block.timestamp;
    console.log("\n=== Scenario:", scenarioName, "===");
    console.log("Start time:", block.timestamp);

    for (uint256 i; i < actions.length; i++) {
      ScenarioAction memory action = actions[i];

      if (action.timeWarp > 0) {
        actionTimeWarp(action.timeWarp);
      }

      _logAction(action);
      _executeAction(action);
    }

    console.log("=== Scenario Complete ===\n");
  }

  /**
   * @notice Register multiple vaults for multi-chain simulation
   * @param vaultConfigs Array of vault configurations
   */
  function _registerVaults(
    VaultConfig[] memory vaultConfigs
  ) internal {
    multiVaultMode = vaultConfigs.length > 1;

    for (uint256 i; i < vaultConfigs.length; i++) {
      vaults.push(vaultConfigs[i]);
    }

    if (multiVaultMode) {
      console.log("\n=== Multi-Vault Mode Enabled ===");
      console.log("Tracking", vaults.length, "vaults");
      for (uint256 i; i < vaults.length; i++) {
        console.log("Vault", i, ":", vaults[i].name);
      }
      console.log("==================================\n");
    }
  }

  /**
   * @notice Log action details in single-line format
   * @dev Format: "Action by Actor for Amount expected to OUTCOME after X hours"
   */
  function _logAction(ScenarioAction memory action) private view {
    string memory actorName = actorNames[action.actor];

    IERC20 currentAsset = multiVaultMode
      ? vaults[action.vaultIndex].asset
      : asset;
    string memory assetSymbol = IERC20Metadata(address(currentAsset))
      .symbol();

    if (multiVaultMode) {
      console.log(vaults[action.vaultIndex].name);
    }
    string memory outcome = action.expected == ExpectedOutcome.Success
      ? "SUCCEED"
      : "REVERT";

    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    uint8 vaultDecimals = IERC20Metadata(address(vault)).decimals();

    // Build single-line log message
    string memory logMessage = "";

    // Action type and actor
    if (action.actionType == ActionType.Deposit) {
      (uint256 assets, ) = abi.decode(
        action.args,
        (uint256, address)
      );
      string memory amount = string(
        abi.encodePacked(assets / (10 ** assetDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Deposit by ",
          actorName,
          " for ",
          amount,
          " ",
          assetSymbol
        )
      );
    } else if (action.actionType == ActionType.Withdraw) {
      (uint256 assets, , ) = abi.decode(
        action.args,
        (uint256, address, address)
      );
      string memory amount = string(
        abi.encodePacked(assets / (10 ** assetDecimals))
      );
      logMessage = string(
        abi.encodePacked(
          "Withdraw by ",
          actorName,
          " for ",
          amount,
          " ",
          assetSymbol
        )
      );
    } else if (action.actionType == ActionType.HarvestFees) {
      logMessage = "Harvest fees";
    } else if (action.actionType == ActionType.TimeWarp) {
      uint256 timeJump = abi.decode(action.args, (uint256));
      logMessage = string(
        abi.encodePacked(
          "Time warp for ",
          timeJump / 1 hours,
          " hours"
        )
      );
    } else if (action.actionType == ActionType.DepositToBuffer) {
      uint256 assets = abi.decode(action.args, (uint256));
      string memory amount = string(
        abi.encodePacked(assets / (10 ** assetDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Deposit to buffer by ",
          actorName,
          " for ",
          amount,
          " ",
          assetSymbol
        )
      );
    } else if (action.actionType == ActionType.SkimBuffer) {
      uint256 assets = abi.decode(action.args, (uint256));
      string memory amount = string(
        abi.encodePacked(assets / (10 ** assetDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Skim buffer by ",
          actorName,
          " for ",
          amount,
          " ",
          assetSymbol
        )
      );
    } else if (action.actionType == ActionType.RequestWithdrawal) {
      (uint256 shares, ) = abi.decode(
        action.args,
        (uint256, uint256)
      );
      string memory amount = string(
        abi.encodePacked(shares / (10 ** vaultDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Request withdrawal by ",
          actorName,
          " for ",
          amount,
          " shares"
        )
      );
    } else if (action.actionType == ActionType.ProcessRequests) {
      logMessage = string(
        abi.encodePacked("Process withdrawal requests by ", actorName)
      );
    } else if (action.actionType == ActionType.MigrateLToken) {
      uint256 lTokens = abi.decode(action.args, (uint256));
      string memory amount = string(
        abi.encodePacked(lTokens / (10 ** assetDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Migrate LToken by ",
          actorName,
          " for ",
          amount,
          " l-tokens"
        )
      );
    } else if (action.actionType == ActionType.UpdateAPR) {
      uint256 newAPR = abi.decode(action.args, (uint256));
      logMessage = string(
        abi.encodePacked(
          "Update APR to ",
          (newAPR / RAY) * 10,
          ".",
          (newAPR % RAY) / (RAY / 100)
        )
      );
    } else if (action.actionType == ActionType.Redeem) {
      (uint256 shares, , ) = abi.decode(
        action.args,
        (uint256, address, address)
      );
      string memory amount = string(
        abi.encodePacked(shares / (10 ** vaultDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Redeem by ",
          actorName,
          " for ",
          amount,
          " shares"
        )
      );
    } else if (action.actionType == ActionType.Mint) {
      (uint256 shares, ) = abi.decode(
        action.args,
        (uint256, address)
      );
      string memory amount = string(
        abi.encodePacked(shares / (10 ** vaultDecimals))
      );

      logMessage = string(
        abi.encodePacked(
          "Mint by ",
          actorName,
          " for ",
          amount,
          " shares"
        )
      );
    }

    // Expected outcome
    logMessage = string(
      abi.encodePacked(logMessage, " expected to ", outcome)
    );

    // Time warp (if any)
    if (action.timeWarp > 0) {
      logMessage = string(
        abi.encodePacked(
          logMessage,
          " after ",
          action.timeWarp / 1 hours,
          " hours"
        )
      );
    }

    console.log(logMessage);
  }

  /**
   * @notice Execute a single action based on type
   */
  function _executeAction(ScenarioAction memory action) private {
    bool expectSuccess = action.expected == ExpectedOutcome.Success;

    LedgityYieldVault currentVault = multiVaultMode
      ? vaults[action.vaultIndex].vault
      : vault;
    IERC20 currentAsset = multiVaultMode
      ? vaults[action.vaultIndex].asset
      : asset;

    if (action.actionType == ActionType.Deposit) {
      (uint256 amount, address receiver) = abi.decode(
        action.args,
        (uint256, address)
      );

      actionDeposit(
        currentVault,
        currentAsset,
        action.actor,
        receiver,
        amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.Mint) {
      (uint256 shares, address receiver) = abi.decode(
        action.args,
        (uint256, address)
      );

      actionMint(
        currentVault,
        currentAsset,
        action.actor,
        receiver,
        shares,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.Withdraw) {
      (uint256 assets, address receiver, address owner) = abi.decode(
        action.args,
        (uint256, address, address)
      );

      actionWithdraw(
        currentVault,
        currentAsset,
        action.actor,
        receiver,
        owner,
        assets,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.Redeem) {
      (uint256 shares, address receiver, address owner) = abi.decode(
        action.args,
        (uint256, address, address)
      );

      actionRedeem(
        currentVault,
        currentAsset,
        action.actor,
        receiver,
        owner,
        shares,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.RequestWithdrawal) {
      (uint256 shares, uint256 gasFee) = abi.decode(
        action.args,
        (uint256, uint256)
      );

      actionRequestWithdrawal(
        currentVault,
        action.actor,
        shares,
        gasFee,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.ProcessRequests) {
      (uint256[] memory requestIds, uint256 addAssets) = abi.decode(
        action.args,
        (uint256[], uint256)
      );

      actionProcessRequests(
        currentVault,
        currentAsset,
        action.actor,
        requestIds,
        addAssets,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.DepositToBuffer) {
      uint256 amount = abi.decode(action.args, (uint256));

      actionDepositToBuffer(
        currentVault,
        currentAsset,
        action.actor,
        amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.SkimBuffer) {
      uint256 amount = abi.decode(action.args, (uint256));

      actionSkimBuffer(
        currentVault,
        action.actor,
        amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.HarvestFees) {
      actionHarvestFees(
        currentVault,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.MigrateLToken) {
      uint256 amount = abi.decode(action.args, (uint256));

      actionMigrateLToken(
        currentVault,
        action.actor,
        amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.UpdateAPR) {
      uint256 newAPR = abi.decode(action.args, (uint256));

      actionUpdateAPR(
        currentVault,
        action.actor,
        newAPR,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.UpdateFees) {
      (
        uint256 managementFee,
        uint256 performanceFee,
        uint256 withdrawalFee
      ) = abi.decode(action.args, (uint256, uint256, uint256));

      actionUpdateFees(
        currentVault,
        action.actor,
        managementFee,
        performanceFee,
        withdrawalFee,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.SetTotalAssets) {
      uint256 amount = abi.decode(action.args, (uint256));

      actionSetTotalAssets(
        currentVault,
        action.actor,
        amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.TimeWarp) {
      uint256 timeJump = abi.decode(action.args, (uint256));
      actionTimeWarp(timeJump);
    }
  }
}
