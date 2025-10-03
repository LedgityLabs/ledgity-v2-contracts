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
 * @title YieldVault_MultiChain_ScenarioTest
 * @notice Multi-chain simulation tests for LedgityYieldVault
 * @dev Tests vault synchronization across different "chains" (different assets)
 */
contract YieldVault_MultiChain_ScenarioTest is ScenarioEngine {
  MockLToken public lTokenUsdc;
  MockLToken public lTokenUsdcMock;

  function setUp() public {
    _setUp();

    // Create two vaults simulating different chains
    lTokenUsdc = _createLToken(usdc);
    lTokenUsdcMock = _createLToken(mockUsdc);

    LedgityYieldVault vaultUsdc = _createVault(
      usdc,
      IERC20(address(lTokenUsdc))
    );
    LedgityYieldVault vaultUsdcMock = _createVault(
      mockUsdc,
      IERC20(address(lTokenUsdcMock))
    );

    // Register vaults for multi-chain simulation
    VaultConfig[] memory vaultConfigs = new VaultConfig[](2);
    vaultConfigs[0] = VaultConfig({
      vault: vaultUsdc,
      asset: usdc,
      name: "Base-USDC"
    });
    vaultConfigs[1] = VaultConfig({
      vault: vaultUsdcMock,
      asset: mockUsdc,
      name: "Arbitrum-USDC"
    });

    _registerVaults(vaultConfigs);

    // Setup approvals
    _setupApprovalsForVault(vaultUsdc, usdc);
    _setupApprovalsForVault(vaultUsdcMock, mockUsdc);

    // Give users initial balances
    deal(address(usdc), testAccount1, 1000000 * 1e6);
    deal(address(usdc), testAccount2, 1000000 * 1e6);
    deal(address(usdc), testAccount3, 1000000 * 1e6);
    deal(address(mockUsdc), testAccount1, 1000000 * 1e6);
    deal(address(mockUsdc), testAccount2, 1000000 * 1e6);
    deal(address(mockUsdc), testAccount3, 1000000 * 1e6);
  }

  /**
   * @notice Scenario: Synchronized deposits across chains
   * @dev Tests that identical deposits on different chains maintain sync
   */
  function test_scenario_synchronizedDeposits() public {
    ScenarioAction[] memory actions = new ScenarioAction[](6);

    // Alice deposits on Base
    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Alice deposits on Arbitrum
    actions[1] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Time passes
    actions[2] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(30 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Bob deposits on Base
    actions[3] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(50000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Bob deposits on Arbitrum
    actions[4] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(50000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Harvest fees on both chains
    actions[5] = ScenarioAction({
      actionType: ActionType.HarvestFees,
      actor: testAccount1,
      args: Args.none(),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    executeScenario(actions, "Synchronized Deposits");
  }

  /**
   * @notice Scenario: Asymmetric activity across chains
   * @dev Tests that vaults stay in sync even with different activity patterns
   */
  function test_scenario_asymmetricActivity() public {
    ScenarioAction[] memory actions = new ScenarioAction[](12);

    // Initial deposits on both chains
    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[1] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Time passes
    actions[2] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(15 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Heavy activity on Base only
    actions[3] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(75000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[4] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount3,
      args: Args.deposit(50000 * 1e6, testAccount3),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Time passes
    actions[5] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(20 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Some activity on Arbitrum
    actions[6] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(30000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Harvest fees on both
    actions[7] = ScenarioAction({
      actionType: ActionType.HarvestFees,
      actor: testAccount1,
      args: Args.none(),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[8] = ScenarioAction({
      actionType: ActionType.HarvestFees,
      actor: testAccount1,
      args: Args.none(),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // More time
    actions[9] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(25 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Withdrawals on Base
    actions[10] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      args: Args.withdraw(20000 * 1e6, testAccount1, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Withdrawal on Arbitrum
    actions[11] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      args: Args.withdraw(20000 * 1e6, testAccount1, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    executeScenario(actions, "Asymmetric Activity");
  }

  /**
   * @notice Scenario: Long-term yield accrual with periodic harvesting
   * @dev Tests vault behavior over extended periods with regular fee collection
   */
  function test_scenario_longTermYieldAccrual() public {
    ScenarioAction[] memory actions = new ScenarioAction[](20);
    uint256 idx = 0;

    // Initial deposits
    actions[idx++] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[idx++] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Simulate 6 months with monthly harvests
    for (uint256 i; i < 6; i++) {
      // Time passes (30 days)
      actions[idx++] = ScenarioAction({
        actionType: ActionType.TimeWarp,
        actor: testAccount1,
        args: Args.timeWarp(30 days),
        timeWarp: 0,
        expected: ExpectedOutcome.Success,
        revertMessage: "",
        vaultIndex: 0
      });

      // Harvest fees on Base
      actions[idx++] = ScenarioAction({
        actionType: ActionType.HarvestFees,
        actor: testAccount1,
        args: Args.none(),
        timeWarp: 0,
        expected: ExpectedOutcome.Success,
        revertMessage: "",
        vaultIndex: 0
      });

      // Harvest fees on Arbitrum
      if (idx < 20) {
        actions[idx++] = ScenarioAction({
          actionType: ActionType.HarvestFees,
          actor: testAccount1,
          args: Args.none(),
          timeWarp: 0,
          expected: ExpectedOutcome.Success,
          revertMessage: "",
          vaultIndex: 1
        });
      }
    }

    executeScenario(actions, "Long-term Yield Accrual");

    // Validate final state
    LedgityYieldVault vaultUsdc = vaults[0].vault;
    LedgityYieldVault vaultUsdcMock = vaults[1].vault;

    uint256 sharePriceUsdc = vaultUsdc.convertToAssets(1e6);
    uint256 sharePriceUsdcMock = vaultUsdcMock.convertToAssets(1e6);

    // Both should have appreciated
    assertGt(
      sharePriceUsdc,
      1e6,
      "USDC vault should have appreciated"
    );
    assertGt(
      sharePriceUsdcMock,
      1e6,
      "MockUSDC vault should have appreciated"
    );

    console.log("\n=== Final Share Prices ===");
    console.log("USDC vault:", sharePriceUsdc);
    console.log("MockUSDC vault:", sharePriceUsdcMock);
  }

  /**
   * @notice Scenario: Buffer operations across chains
   * @dev Tests buffer management stays consistent across vaults
   */
  function test_scenario_bufferOperationsMultiChain() public {
    ScenarioAction[] memory actions = new ScenarioAction[](14);

    // Initial deposits
    actions[0] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[1] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount1,
      args: Args.deposit(100000 * 1e6, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Buffer operations on Base
    actions[2] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      args: Args.depositToBuffer(30000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Buffer operations on Arbitrum
    actions[3] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      args: Args.depositToBuffer(30000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Time passes
    actions[4] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(15 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Skim buffer on Base
    actions[5] = ScenarioAction({
      actionType: ActionType.SkimBuffer,
      actor: liquidityManager,
      args: Args.skimBuffer(10000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Skim buffer on Arbitrum
    actions[6] = ScenarioAction({
      actionType: ActionType.SkimBuffer,
      actor: liquidityManager,
      args: Args.skimBuffer(10000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // More deposits
    actions[7] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(40000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[8] = ScenarioAction({
      actionType: ActionType.Deposit,
      actor: testAccount2,
      args: Args.deposit(40000 * 1e6, testAccount2),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Time passes
    actions[9] = ScenarioAction({
      actionType: ActionType.TimeWarp,
      actor: testAccount1,
      args: Args.timeWarp(20 days),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    // Withdrawals
    actions[10] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      args: Args.withdraw(15000 * 1e6, testAccount1, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[11] = ScenarioAction({
      actionType: ActionType.Withdraw,
      actor: testAccount1,
      args: Args.withdraw(15000 * 1e6, testAccount1, testAccount1),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    // Final buffer operations
    actions[12] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      args: Args.depositToBuffer(20000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 0
    });

    actions[13] = ScenarioAction({
      actionType: ActionType.DepositToBuffer,
      actor: liquidityManager,
      args: Args.depositToBuffer(20000 * 1e6),
      timeWarp: 0,
      expected: ExpectedOutcome.Success,
      revertMessage: "",
      vaultIndex: 1
    });

    executeScenario(actions, "Buffer Operations Multi-Chain");
  }
}
