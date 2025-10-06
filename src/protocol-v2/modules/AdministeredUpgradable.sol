// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGlobalOwner } from "src/protocol-v2/interfaces/IGlobalOwner.sol";
import { IGlobalPause } from "src/protocol-v2/interfaces/IGlobalPause.sol";
import { IGlobalAccessList } from "src/protocol-v2/interfaces/IGlobalAccessList.sol";

/**
 * @title AdministeredUpgradable
 * @notice Abstract base contract providing administration features for upgradeable contracts
 * @dev This contract integrates with global administration contracts (GlobalOwner, GlobalPause, GlobalRestrict)
 *      to provide centralized ownership, pause functionality, and blacklist management across the protocol.
 *      It implements UUPS upgradeability pattern and includes token recovery functionality.
 *
 *      Key features:
 *      - Global ownership management through IGlobalOwner
 *      - Global pause functionality through IGlobalPause
 *      - Global blacklist integration through IGlobalAccessList
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

  error UserIsRestricted();

  // =========== STORAGE =========== //

  IGlobalOwner public globalOwner;
  IGlobalPause public globalPause;
  IGlobalAccessList public globalRestrict;

  bool public isPausedLocal;

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
   * @param globalRestrict_ The address of the GlobalRestrict contract.
   */
  function __AdministeredUpgradable_init(
    address globalOwner_,
    address globalPause_,
    address globalRestrict_
  ) internal onlyInitializing {
    __UUPSUpgradeable_init();
    __Pausable_init_unchained();
    __Ownable_init_unchained();

    globalOwner = IGlobalOwner(globalOwner_);
    globalPause = IGlobalPause(globalPause_);
    globalRestrict = IGlobalAccessList(globalRestrict_);

    _transferOwnership(globalOwner.owner());
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
  function paused()
    public
    view
    override(PausableUpgradeable)
    returns (bool)
  {
    return isPausedLocal || globalPause.paused();
  }

  /**
   * @notice Pauses the contract.
   */
  function pauseLocal() external onlyOwner {
    isPausedLocal = true;
    emit Paused(msg.sender);
  }

  /**
   * @notice Unpauses the contract.
   */
  function unpauseLocal() external onlyOwner {
    isPausedLocal = false;
    emit Unpaused(msg.sender);
  }

  // =========== RESTRICTIONS =========== //

  /**
   * @notice Reverts if the given account is restricted by the GlobalRestrict contract.
   * @param account Address to verify.
   */
  modifier notRestricted(address account) {
    if (globalRestrict.isRestricted(account))
      revert UserIsRestricted();
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
