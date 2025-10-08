// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Libraries
import { HederaResponseCodes } from "src/protocol-v2/chainHedera/libraries/HederaResponseCodes.sol";
// Interfaces
import { IHederaTokenService } from "src/protocol-v2/chainHedera/interfaces/IHederaTokenService.sol";

/**
 * @title HederaAssociateToken
 * @notice Register a contract on Hedera Token Registry
 */
abstract contract HederaAssociateToken {
  error FailedToAssociateTokens();

  function _associateToken(address asset) internal {
    int64 associateResponse = IHederaTokenService(address(0x167))
      .associateToken(address(this), asset);

    if (associateResponse != HederaResponseCodes.SUCCESS) {
      revert FailedToAssociateTokens();
    }
  }
}
