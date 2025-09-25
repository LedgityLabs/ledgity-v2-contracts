// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @title IGlobalAccessList
 * @notice Interface for the GlobalAccessList contract that manages restricted accounts.
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
interface IGlobalAccessList {
  // =========== ERRORS =========== //

  /// @notice Thrown when trying to restrict an account that is already restricted
  error AccountAlreadyRestricted();
  /// @notice Thrown when trying to unrestrict an account that is not restricted
  error AccountNotRestricted();

  // =========== EVENTS =========== //

  /// @notice Emitted when an account is added to the restricted list
  /// @param account The address of the restricted account
  event RestrictAccount(address indexed account);
  /// @notice Emitted when an account is removed from the restricted list
  /// @param account The address of the unrestricted account
  event UnrestrictAccount(address indexed account);

  // =========== READ FUNCTIONS =========== //

  /**
   * @notice Checks whether a given account is restricted.
   * @param account Address of the account to check.
   * @return True if the account is restricted, false otherwise
   */
  function isRestricted(address account) external view returns (bool);

  /**
   * @notice Returns a paginated list of restricted accounts.
   * @param startIndex The index of the first account to return.
   * @param nbAccounts The number of accounts to return.
   * @return accounts An array of restricted accounts addresses.
   */
  function getRestrictedAccounts(
    uint256 startIndex,
    uint256 nbAccounts
  ) external view returns (address[] memory accounts);

  // =========== WRITE FUNCTIONS =========== //

  /**
   * @notice Adds a given account to the restricted list.
   * @dev Only callable by the contract owner.
   * @param account The account's address to be restricted.
   */
  function restrictAccount(address account) external;

  /**
   * @notice Removes a given account from the restricted list.
   * @dev Only callable by the contract owner. Uses swap-and-pop for gas efficiency.
   * @param account The account's address to be unrestricted.
   */
  function unRestrictAccount(address account) external;
}
