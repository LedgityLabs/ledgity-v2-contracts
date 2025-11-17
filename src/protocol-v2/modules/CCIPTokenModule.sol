// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// Interfaces
import { IGetCCIPAdmin } from "@chainlink/contracts-ccip/contracts/interfaces/IGetCCIPAdmin.sol";
import { IBurnMintERC20 } from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";

// ======== ERRORS ======== //

error ZeroAddressCCIPAdmin();
error MustImplementMintAndBurnFunctions();
error SenderNotMinter(address sender);
error SenderNotBurner(address sender);
error SenderNotCCIPAdmin(address sender);
error InsufficientAllowance();

/**
 * @title CCIPTokenModule
 * @notice A module that adds CCIP compatibility features to ERC20 tokens
 * @dev This contract is designed to be imported and used to extend your existing token
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract CCIPTokenModule is IGetCCIPAdmin, ERC20Upgradeable {
  // ======== STORAGE ======== //
  // Role management state
  mapping(address => bool) private _minters;
  mapping(address => bool) private _burners;

  // CCIP admin
  address private _ccipAdmin;

  // ======== EVENTS ======== //

  // Events for role management
  event MintAccessGranted(address indexed minter);
  event BurnAccessGranted(address indexed burner);
  event MintAccessRevoked(address indexed minter);
  event BurnAccessRevoked(address indexed burner);
  event CCIPAdminChanged(address indexed newAdmin);

  // ======== INITIALIZE ======== //

  /**
   * @notice Initializes the CCIP token
   * @param initialCCIPAdmin The initial CCIP admin address
   */
  function __CCIPCompatible_init(address initialCCIPAdmin) internal {
    _ccipAdmin = initialCCIPAdmin;

    bool successMint = _handleMint(address(0xdead), 0);
    bool successBurn = _handleBurn(address(0xdead), 0);

    // @dev Revert if child contracts do not implement _handleMint and _handleBurn
    if (!successMint || !successBurn)
      revert MustImplementMintAndBurnFunctions();
  }

  // ======== VIRTUAL ======== //

  /**
   * @notice Virtual function that enables handling of asset balance on mint
   */
  function _handleMint(
    address /* account */,
    uint256 /* amount */
  ) internal virtual returns (bool) {}

  /**
   * @notice Virtual function that enables handling of asset balance on burn
   */
  function _handleBurn(
    address /* account */,
    uint256 /* amount */
  ) internal virtual returns (bool) {}

  // ======== MODIFIERS ======== //

  /**
   * @notice Checks if the sender is the CCIP admin
   */
  modifier onlyCCIPAdmin() {
    if (msg.sender != _ccipAdmin)
      revert SenderNotCCIPAdmin(msg.sender);
    _;
  }

  // ======== VIEWS ======== //

  /**
   * @notice Gets the CCIP admin address
   * @return The CCIP admin address
   */
  function getCCIPAdmin() external view returns (address) {
    return _ccipAdmin;
  }

  /**
   * @notice Checks if an account has the minter role
   * @param account The account to check
   * @return True if the account has the role
   */
  function isMinter(address account) public view returns (bool) {
    return _minters[account];
  }

  /**
   * @notice Checks if an account has the burner role
   * @param account The account to check
   * @return True if the account has the role
   */
  function isBurner(address account) public view returns (bool) {
    return _burners[account];
  }

  // ======== BURN & MINT ======== //

  /**
   * @notice Implementation of mints tokens to a specified account
   * @param account Account to mint to
   * @param amount Amount to mint
   */
  function mint(address account, uint256 amount) external {
    if (!isMinter(msg.sender)) revert SenderNotMinter(msg.sender);

    _handleMint(account, amount);
  }

  /**
   * @notice Implementation of burns tokens from caller's account
   * @param amount Amount to burn
   */
  function burn(uint256 amount) public {
    if (!isBurner(msg.sender)) revert SenderNotBurner(msg.sender);

    _handleBurn(msg.sender, amount);
  }

  // ======== ADMIN ======== //

  /**
   * @notice Sets the CCIP admin address
   * @param newAdmin The new CCIP admin address
   */
  function setCCIPAdmin(address newAdmin) external onlyCCIPAdmin {
    if (newAdmin == address(0)) revert ZeroAddressCCIPAdmin();

    _ccipAdmin = newAdmin;
    emit CCIPAdminChanged(newAdmin);
  }

  /**
   * @notice Grants minter role to an account
   * @param minter The account to grant the role to
   */
  function grantMintRole(address minter) external onlyCCIPAdmin {
    _minters[minter] = true;
    emit MintAccessGranted(minter);
  }

  /**
   * @notice Revokes minter role from an account
   * @param minter The account to revoke the role from
   */
  function revokeMintRole(address minter) external onlyCCIPAdmin {
    _minters[minter] = false;
    emit MintAccessRevoked(minter);
  }

  /**
   * @notice Grants burner role to an account
   * @param burner The account to grant the role to
   */
  function grantBurnRole(address burner) external onlyCCIPAdmin {
    _burners[burner] = true;
    emit BurnAccessGranted(burner);
  }

  /**
   * @notice Revokes burner role from an account
   * @param burner The account to revoke the role from
   */
  function revokeBurnRole(address burner) external onlyCCIPAdmin {
    _burners[burner] = false;
    emit BurnAccessRevoked(burner);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[49] private __gap;
}
