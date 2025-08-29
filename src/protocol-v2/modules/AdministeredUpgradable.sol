// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Contracts
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGlobalOwner } from "src/protocol-v2/interfaces/IGlobalOwner.sol";
import { IGlobalPause } from "src/protocol-v2/interfaces/IGlobalPause.sol";
import { IGlobalBlacklist } from "src/protocol-v2/interfaces/IGlobalBlacklist.sol";

/**
 * @title AdministeredUpgradable
 * @notice Abstract base contract providing administration features for upgradeable contracts
 * @dev This contract integrates with global administration contracts (GlobalOwner, GlobalPause, GlobalBlacklist)
 *      to provide centralized ownership, pause functionality, and blacklist management across the protocol.
 *      It implements UUPS upgradeability pattern and includes token recovery functionality.
 *
 *      Key features:
 *      - Global ownership management through IGlobalOwner
 *      - Global pause functionality through IGlobalPause
 *      - Global blacklist integration through IGlobalBlacklist
 *      - UUPS upgradeable pattern with owner-restricted upgrades
 *      - ERC20 token recovery for admin purposes
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
abstract contract AdministeredUpgradable is
  Initializable,
  UUPSUpgradeable,
  PausableUpgradeable,
  OwnableUpgradeable
{
  // =========== ERRORS =========== //

  error UserIsBlacklisted();

  // =========== STORAGE =========== //

  IGlobalOwner public globalOwner;
  IGlobalPause public globalPause;
  IGlobalBlacklist public globalBlacklist;

  // =========== CONSTRUCTOR & INITIALIZER =========== //

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializer functions of the contract. They replace the constructor()
   * function in the context of upgradeable contracts.
   * @dev See: https://docs.openzeppelin.com/contracts/4.x/upgradeable
   * @param globalOwner_ The address of the GlobalOwner contract.
   * @param globalPause_ The address of the GlobalPause contract.
   * @param globalBlacklist_ The address of the GlobalBlacklist contract.
   */
  function __AdministeredUpgradable_init(
    address globalOwner_,
    address globalPause_,
    address globalBlacklist_
  ) internal onlyInitializing {
    __UUPSUpgradeable_init();
    __Pausable_init_unchained();
    __Ownable_init_unchained();

    globalOwner = IGlobalOwner(globalOwner_);
    globalPause = IGlobalPause(globalPause_);
    globalBlacklist = IGlobalBlacklist(globalBlacklist_);

    transferOwnership(globalOwner.owner());
  }

  // =========== UPGRADABLE =========== //

  /**
   * @notice Override of UUPSUpgradeable._authorizeUpgrade() function restricted to
   * global owner. It is called by the proxy contract during an upgrade.
   * @param newImplementation The address of the new implementation contract.
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyOwner {}

  // =========== OWNABLE =========== //

  /**
   * @notice Returns the owner of the contract
   * @return The owner's address
   */
  function owner() public view virtual override returns (address) {
    return globalOwner.owner();
  }

  // =========== PAUSABLE =========== //

  /**
   * @notice Override of PausableUpgradeable.pause() that retrieves the pause state
   * from the GlobalPause contract instead.
   * @return Whether the contract is paused or not.
   */
  function paused() public view override returns (bool) {
    return globalPause.paused();
  }

  // =========== BLACKLIST =========== //

  /**
   * @notice Reverts if the given account is blacklisted by the GlobalBlacklist contract.
   * @param account Address to verify.
   */
  modifier notBlacklisted(address account) {
    if (globalBlacklist.isBlacklisted(account))
      revert UserIsBlacklisted();
    _;
  }

  // =========== RECOVERABLE =========== //

  /**
   * @notice Recovers a specified amount of a given token address.
   * @param tokenAddress The address of the token to recover.
   * @param amount The amount of the token to recover.
   */
  function recoverERC20(
    address tokenAddress,
    uint256 amount
  ) public onlyOwner {
    if (tokenAddress == address(0)) {
      payable(msg.sender).transfer(amount);
    } else {
      // slither-disable-next-line unchecked-transfer
      IERC20(tokenAddress).transfer(msg.sender, amount);
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
