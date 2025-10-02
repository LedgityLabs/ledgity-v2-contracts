// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Engine
import { ScenarioEngine } from "tests/protocol-v2/scenarios/engine/ScenarioEngine.sol";
// Helpers
import { Args } from "tests/protocol-v2/helpers/scenarios/ScenarioEncodeArgs.sol";
// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { MockLToken } from "src/protocol-v1/mock/MockLToken.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title YieldVault_ScenarioTest
 * @notice Scenario-based tests for LedgityYieldVault using struct arrays
 * @dev Tests specific user journeys with deterministic action sequences
 */
contract Skip_YieldVault_ScenarioTest is ScenarioEngine {
  MockLToken public lToken;

  function setUp() public {
    _setUp();

    asset = mockWeth;
    lToken = _createLToken(asset);
    vault = _createVault(asset, IERC20(address(lToken)));

    _setupApprovalsForVault(vault, asset);

    // Give users initial balances
    deal(address(asset), testAccount1, 1000000 * 1e18);
    deal(address(asset), testAccount2, 1000000 * 1e18);
    deal(address(asset), testAccount3, 1000000 * 1e18);
  }

  // ======== COMPLEX STATE SCENARIOS ======== //

  /**
   * @notice Scenario: Complex multi-user interactions with yield and fees
   * @dev Tests state coherence across deposits, time, yield accrual, and fee collection
   */
  function test_scenario_complexMultiUserInteractions() public {
    ScenarioAction[] memory actions = new ScenarioAction[](10);

    // Initial deposits
    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      amount: 100000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[1] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      amount: 50000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Time passes, yield accrues
    actions[2] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      amount: 30 days,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Charlie deposits after yield
    actions[3] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount3,
      amount: 75000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // More time passes
    actions[4] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      amount: 60 days,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Harvest fees
    actions[5] = ScenarioAction({
      actionType: ActionType.HarvestFees,
      actor: testAccount1,
      amount: 0,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Buffer operations
    actions[6] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      amount: 50000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Alice withdraws part
    actions[7] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      amount: 30000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // More time and yield
    actions[8] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      amount: 15 days,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Final deposit
    actions[9] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      amount: 25000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    // Execute scenario
    executeScenario(actions, "Complex Multi-User Interactions");

    // Validate final state coherence
    uint256 aliceShares = vault.balanceOf(testAccount1);
    uint256 bobShares = vault.balanceOf(testAccount2);
    uint256 charlieShares = vault.balanceOf(testAccount3);
    uint256 feeRecipientShares = vault.balanceOf(feeRecipient);
    uint256 totalSupply = vault.totalSupply();
    uint256 totalAssets = vault.totalAssets();
    uint256 bufferAssets = vault.getBufferAssets();

    // Core invariants
    assertGt(aliceShares, 0, "Alice should have shares");
    assertGt(bobShares, 0, "Bob should have shares");
    assertGt(charlieShares, 0, "Charlie should have shares");
    assertGt(
      feeRecipientShares,
      0,
      "Fee recipient should have collected fees"
    );

    // Accounting invariants
    assertEq(
      totalSupply,
      aliceShares + bobShares + charlieShares + feeRecipientShares,
      "Total supply should equal sum of all shares"
    );
    assertGt(
      totalAssets,
      150000 * 1e18,
      "Total assets should have grown with yield"
    );
    assertLe(
      bufferAssets,
      totalAssets,
      "Buffer should not exceed total assets"
    );

    // Share price should have increased due to yield
    uint256 sharePrice = vault.convertToAssets(1e18);
    assertGt(
      sharePrice,
      1e18,
      "Share price should be > 1 due to yield"
    );

    console.log("\n=== Final State ===");
    console.log("Alice shares:", aliceShares);
    console.log("Bob shares:", bobShares);
    console.log("Charlie shares:", charlieShares);
    console.log("Fee recipient shares:", feeRecipientShares);
    console.log("Total supply:", totalSupply);
    console.log("Total assets:", totalAssets);
    console.log("Buffer assets:", bufferAssets);
    console.log("Share price:", sharePrice);
  }

  /**
   * @notice Scenario: Buffer stress test
   * @dev Tests buffer operations under various conditions
   */
  function test_scenario_bufferStressTest() public {
    ScenarioAction[] memory actions = new ScenarioAction[](8);

    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      amount: 100000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[1] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      amount: 50000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[2] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      amount: 30000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[3] = ScenarioAction({
      actionType: ActionType.SkimBuffer,
      actor: liquidityManager,
      amount: 20000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[4] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      amount: 10000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[5] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      amount: 15000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[6] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount3,
      amount: 40000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    actions[7] = ScenarioAction({
      actionType: ActionType.SkimBuffer,
      actor: liquidityManager,
      amount: 10000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.none(),
      vaultIndex: 0
    });

    executeScenario(actions, "Buffer Stress Test");

    // Validate buffer state remains coherent
    uint256 bufferAssets = vault.getBufferAssets();
    uint256 totalAssets = vault.totalAssets();

    assertLe(
      bufferAssets,
      totalAssets,
      "Buffer should never exceed total assets"
    );
    assertGt(bufferAssets, 0, "Buffer should have assets");
    assertGt(totalAssets, 0, "Total assets should be positive");
  }

  /**
   * @notice Scenario: Zero deposit should revert
   */
  function test_scenario_zeroDepositReverts() public {
    ScenarioAction[] memory actions = new ScenarioAction[](1);

    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      amount: 0,
      timeWarp: 0,
      expected: ExpectedOutcome.Revert,
      revertMessage: abi.encodeWithSignature("ZeroAmount()"),
      args: Args.none(),
      vaultIndex: 0
    });

    executeScenario(actions, "Zero Deposit Reverts");
  }

  /**
   * @notice Scenario: Deposit with custom receiver
   * @dev Demonstrates using Args library for custom receivers
   */
  function test_scenario_depositWithCustomReceiver() public {
    ScenarioAction[] memory actions = new ScenarioAction[](3);

    // Alice deposits but Bob receives the shares
    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      amount: 50000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.depositAssets(50000 * 1e18, testAccount2),
      vaultIndex: 0
    });

    // Bob withdraws (he owns the shares)
    actions[1] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount2,
      amount: 10000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.withdrawAssets(10000 * 1e18, testAccount2, testAccount2),
      vaultIndex: 0
    });

    // Charlie mints shares for himself
    actions[2] = ScenarioAction({
      actionType: ActionType.Mint,
      actor: testAccount3,
      amount: 30000 * 1e18,
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      args: Args.mintShares(30000 * 1e18, testAccount3),
      vaultIndex: 0
    });

    executeScenario(actions, "Deposit with Custom Receiver");

    // Validate Bob received shares from Alice's deposit
    uint256 bobShares = vault.balanceOf(testAccount2);
    assertGt(
      bobShares,
      0,
      "Bob should have shares from Alice's deposit"
    );

    // Validate Charlie has shares
    uint256 charlieShares = vault.balanceOf(testAccount3);
    assertGt(charlieShares, 0, "Charlie should have shares");

    // Validate Alice has no shares (she deposited for Bob)
    uint256 aliceShares = vault.balanceOf(testAccount1);
    assertEq(aliceShares, 0, "Alice should have no shares");
  }
}
