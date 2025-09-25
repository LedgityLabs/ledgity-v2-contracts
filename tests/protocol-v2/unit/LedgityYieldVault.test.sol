// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";

contract VaultComputationsTest is Fixtures {
  function setUp() public {
    _setUp();
  }
}
