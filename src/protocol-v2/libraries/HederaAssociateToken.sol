// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Libraries
import { HederaResponseCodes } from "src/protocol-v2/chainHedera/libs/HederaResponseCodes.sol";
// Interfaces
import { IHederaTokenService } from "src/protocol-v2/chainHedera/interfaces/IHederaTokenService.sol";

/**
 * @title HederaAssociateToken
 * @notice Register a contract on Hedera Token Registry
 */
library HederaAssociateToken {
  error FailedToAssociateTokens();

  function associateToken(address asset) public {
    int64 associateResponse = IHederaTokenService(address(0x167))
      .associateToken(address(this), asset);

    if (associateResponse != HederaResponseCodes.SUCCESS) {
      revert FailedToAssociateTokens();
    }
  }
}
