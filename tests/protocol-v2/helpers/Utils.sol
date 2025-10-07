// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

library Utils {
  function toUpperCase(string memory str) internal pure returns (string memory) {
    bytes memory bStr = bytes(str);
    bytes memory bUpper = new bytes(bStr.length);
    
    for (uint256 i = 0; i < bStr.length; i++) {
      // If character is lowercase (a-z), convert to uppercase
      if (bStr[i] >= 0x61 && bStr[i] <= 0x7A) {
        bUpper[i] = bytes1(uint8(bStr[i]) - 32);
      } else {
        bUpper[i] = bStr[i];
      }
    }
    
    return string(bUpper);
  }
}
