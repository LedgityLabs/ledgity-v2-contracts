// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
import { ScenarioActions } from "tests/protocol-v2/helpers/ScenarioActions.sol";
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
    Withdraw,
    RequestWithdrawal,
    ProcessRequests,
    DepositToBuffer,
    SkimBuffer,
    HarvestFees,
    TimeWarp,
    UpdateAPR,
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
    uint256 amount;
    uint256 timeWarp;
    ExpectedOutcome expected;
    bytes revertMessage;
  }

  // ======== STATE ======== //

  LedgityYieldVault internal vault;
  IERC20 internal asset;
  uint256 internal scenarioStartTime;

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
   * @notice Log action details in single-line format
   * @dev Format: "Action by Actor for Amount expected to OUTCOME after X hours"
   */
  function _logAction(ScenarioAction memory action) private view {
    string memory actorName = actorNames[action.actor];
    string memory assetSymbol = IERC20Metadata(address(asset))
      .symbol();
    string memory outcome = action.expected == ExpectedOutcome.Success
      ? "SUCCEED"
      : "REVERT";

    uint8 assetDecimals = IERC20Metadata(address(asset)).decimals();
    uint8 vaultDecimals = IERC20Metadata(address(vault)).decimals();

    // Build single-line log message
    string memory logMessage = "";

    // Action type and actor
    if (action.actionType == ActionType.Deposit) {
      string memory amount = string(
        abi.encodePacked(action.amount / (10 ** assetDecimals))
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
      string memory amount = string(
        abi.encodePacked(action.amount / (10 ** assetDecimals))
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
      logMessage = string(abi.encodePacked("Harvest fees"));
    } else if (action.actionType == ActionType.TimeWarp) {
      logMessage = string(
        abi.encodePacked(
          "Time warp for ",
          action.amount / 1 hours,
          " hours"
        )
      );
    } else if (action.actionType == ActionType.DepositToBuffer) {
      string memory amount = string(
        abi.encodePacked(action.amount / (10 ** assetDecimals))
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
      string memory amount = string(
        abi.encodePacked(action.amount / (10 ** assetDecimals))
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
      string memory amount = string(
        abi.encodePacked(action.amount / (10 ** vaultDecimals))
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

    if (action.actionType == ActionType.Deposit) {
      // === DEPOSIT === //

      actionDeposit(
        vault,
        asset,
        action.actor,
        action.amount,
        expectSuccess,
        action.revertMessage
      );
    } else if (action.actionType == ActionType.Withdraw) {
      // === WITHDRAW === //
    } else if (action.actionType == ActionType.RequestWithdrawal) {
      // === REQUEST WITHDRAWAL === //
    } else if (action.actionType == ActionType.DepositToBuffer) {
      // === DEPOSIT TO BUFFER === //
    } else if (action.actionType == ActionType.SkimBuffer) {
      // === SKIM BUFFER === //
    } else if (action.actionType == ActionType.HarvestFees) {
      // === HARVEST FEES === //
    } else if (action.actionType == ActionType.TimeWarp) {
      // === TIME WARP === //

      actionTimeWarp(action.amount);
    }
  }
}
