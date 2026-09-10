// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test } from "foundry/lib/forge-std/src/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
import { VaultLiquidityModule } from "src/protocol-v2/modules/VaultLiquidityModule.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";

contract FeeCheckpointVaultHarness is VaultLiquidityModule {
  function initialize(IERC20 asset_) external initializer {
    __ERC20_init("Fee Checkpoint Vault", "fcVLT");
    __Ownable_init();
    __VaultLiquidityModule_init(
      IVaultLiquidityModule.VaultLiquidityInitParams({
        highWaterMark: 0,
        deploymentDelay: 0,
        initialAssetsPerShare: 0,
        yieldAPR: 0,
        managementFeeRate: 0,
        performanceFeeRate: 0,
        withdrawalFeeRate: 0,
        withdrawalGasFee: 0
      }),
      address(asset_)
    );
  }

  function mintShares(address account, uint256 shares) external {
    _mint(account, shares);
  }

  function harvestFees(address feeRecipient) external {
    _takeFees(feeRecipient);
  }
}

contract FeeCheckpointUnderflowTest is Test {
  MockERC20 internal asset;
  FeeCheckpointVaultHarness internal vault;

  address internal user = address(0xA11CE);
  address internal feeRecipient = address(0xFEE);

  function setUp() public {
    asset = new MockERC20("Mock Asset", "ASSET", 18);
    vault = new FeeCheckpointVaultHarness();
    vault.initialize(IERC20(address(asset)));

    vault.mintShares(user, 100 ether);
    vault.setTotalAssets(100 ether);
  }

  function test_zeroFeeHarvestAdvancesLastFeeTime() public {
    uint256 lastFeeTime = vault.lastFeeTime();

    vm.warp(block.timestamp + 100 days);
    vault.harvestFees(feeRecipient);

    assertGt(vault.lastFeeTime(), lastFeeTime);
    assertEq(vault.lastFeeTime(), block.timestamp);
  }

  function test_enablingMaxLegalFeeAfterStaleCheckpointDoesNotRevert()
    public
  {
    uint256 lastFeeTime = vault.lastFeeTime();

    vm.warp(lastFeeTime + 366 days);
    vault.updateFeeRates(vault.RAY(), 0, 0);

    assertEq(vault.lastFeeTime(), block.timestamp);

    vault.harvestFees(feeRecipient);
  }
}
