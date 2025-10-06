// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// Interfaces
import { IGlobalOwner } from "src/protocol-v2/interfaces/IGlobalOwner.sol";
import { IGlobalAccessList } from "src/protocol-v2/interfaces/IGlobalAccessList.sol";

/**
 * @title GlobalAccessList
 * @notice Contract that manages a list of restricted accounts for access control.
 * @dev This contract is upgradeable and uses UUPS proxy pattern.
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract GlobalAccessList is
  IGlobalAccessList,
  Initializable,
  UUPSUpgradeable,
  OwnableUpgradeable
{
  // =========== STORAGE =========== //

  /// @notice Reference to the GlobalOwner contract
  IGlobalOwner public globalOwner;

  /// @dev Array of restricted accounts
  address[] public restrictedAccounts;
  /// @dev Mapping from account address to its index in the restrictedAccounts array (index + 1, 0 means not restricted)
  mapping(address => uint256) private restrictedAccountsIndex;

  // =========== CONSTRUCTOR & INITIALIZER =========== //

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializer function of the contract. It replaces the constructor()
   * function in the context of upgradeable contracts.
   * @dev See: https://docs.openzeppelin.com/contracts/4.x/upgradeable
   * @param globalOwner_ The address of the GlobalOwner contract.
   */
  function initialize(address globalOwner_) external initializer {
    __UUPSUpgradeable_init();

    globalOwner = IGlobalOwner(globalOwner_);
    _transferOwnership(globalOwner.owner());
  }

  // =========== OVERRIDES =========== //

  /**
   * @notice Override of UUPSUpgradeable._authorizeUpgrade() function restricted to
   * global owner. It is called by the proxy contract during an upgrade.
   * @param newImplementation The address of the new implementation contract.
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyOwner {}

  /**
   * @notice Returns the owner of the contract
   * @dev Overrides OwnableUpgradeable to return the global owner
   * @return The owner's address
   */
  function owner()
    public
    view
    virtual
    override(OwnableUpgradeable)
    returns (address)
  {
    return globalOwner.owner();
  }

  // =========== READ FUNCTIONS =========== //

  /**
   * @notice Checks whether a given account is restricted.
   * @param account Address of the account to check.
   * @return True if the account is restricted, false otherwise
   */
  function isRestricted(
    address account
  ) external view returns (bool) {
    return restrictedAccountsIndex[account] != 0;
  }

  /**
   * @notice Returns a paginated list of restricted accounts.
   * @param startIndex The index of the first account to return.
   * @param nbAccounts The number of accounts to return.
   * @return accounts An array of restricted accounts addresses.
   */
  function getRestrictedAccounts(
    uint256 startIndex,
    uint256 nbAccounts
  ) external view returns (address[] memory) {
    // Handle edge case where startIndex is beyond array length
    if (startIndex >= restrictedAccounts.length) {
      return new address[](0);
    }

    uint256 endIndex = restrictedAccounts.length <
      startIndex + nbAccounts
      ? restrictedAccounts.length
      : startIndex + nbAccounts;

    address[] memory accounts = new address[](endIndex - startIndex);

    for (uint256 i = startIndex; i < endIndex; i++) {
      accounts[i - startIndex] = restrictedAccounts[i];
    }

    return accounts;
  }

  // =========== WRITE FUNCTIONS =========== //

  /**
   * @notice Adds a given account to the restricted list.
   * @dev Only callable by the contract owner.
   * @param account The account's address to be restricted.
   */
  function restrictAccount(address account) external onlyOwner {
    if (restrictedAccountsIndex[account] != 0)
      revert AccountAlreadyRestricted();

    restrictedAccounts.push(account);
    restrictedAccountsIndex[account] = restrictedAccounts.length; // Store index + 1

    emit RestrictAccount(account);
  }

  /**
   * @notice Removes a given account from the restricted list.
   * @dev Only callable by the contract owner. Uses swap-and-pop for gas efficiency.
   * @param account The account's address to be unrestricted.
   */
  function unRestrictAccount(address account) external onlyOwner {
    if (restrictedAccountsIndex[account] == 0)
      revert AccountNotRestricted();

    uint256 indexPlusOne = restrictedAccountsIndex[account];
    uint256 index = indexPlusOne - 1; // Convert back to actual array index
    address lastAccount = restrictedAccounts[
      restrictedAccounts.length - 1
    ];

    // Move the last element to the position of the element to remove
    restrictedAccounts[index] = lastAccount;
    restrictedAccountsIndex[lastAccount] = indexPlusOne; // Keep the +1 offset

    // Remove the account from mapping and array
    restrictedAccountsIndex[account] = 0;
    restrictedAccounts.pop();

    emit UnrestrictAccount(account);
  }

  // =========== PROXY GAP =========== //

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
