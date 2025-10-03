// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
// Libraries
import { HederaAssociateToken } from "src/protocol-v2/chainHedera/libs/HederaAssociateToken.sol";
// Interfaces
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";

/**
 * @title LedgityYieldVaultHedera
 * @notice Ledgity Yield ERC-4626 Vault for RWA assets with on-chain liquidity management and yield generation
 * @notice This contract extends LedgityYieldVault and adds Hedera Token Registry association functionality
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract LedgityYieldVaultHedera is LedgityYieldVault {
  function initializeAndRegister(
    VaultParams calldata params,
    VaultLiquidityInitParams calldata vaultLiquidityInitParams
  ) public {
    HederaAssociateToken.associateToken(address(params.asset));
    LedgityYieldVault.initialize(params, vaultLiquidityInitParams);
  }
}
