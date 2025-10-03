// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
// Libraries
import { SonicFeeMRegister } from "src/protocol-v2/chainSonic/SonicFeeMRegister.sol";
// Interfaces
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";

/**
 * @title LedgityYieldVaultSonic
 * @notice Ledgity Yield ERC-4626 Vault for RWA assets with on-chain liquidity management and yield generation
 * @notice This contract extends LedgityYieldVault and adds Sonic FeeM registration functionality
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract LedgityYieldVaultSonic is LedgityYieldVault {
  function initializeAndRegister(
    VaultParams calldata params,
    VaultLiquidityInitParams calldata vaultLiquidityInitParams
  ) public {
    SonicFeeMRegister.registerContract();
    LedgityYieldVault.initialize(params, vaultLiquidityInitParams);
  }
}
