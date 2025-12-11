// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
// Libraries
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
// Interfaces
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IKrystalVault } from "src/protocol-v2/krystal/IKrystalVault.sol";

/**
 * @title KrystalYieldVault
 * @notice ERC-4626 wrapper for Krystal vault, routing deposits and withdrawals
 * @dev Acts as an intermediary between users and the Krystal vault, providing
 *      a standard ERC-4626 interface for compatibility with DeFi protocols.
 */
contract KrystalYieldVault is
  ERC4626Upgradeable,
  AdministeredUpgradable
{
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using Math for uint256;

  // =========== ERRORS =========== //

  error ZeroAddress();
  error ZeroAmount();
  error InsufficientShares();

  // =========== EVENTS =========== //

  event KrystalVaultUpdated(
    address indexed oldVault,
    address indexed newVault
  );
  event SlippageToleranceUpdated(
    uint256 oldTolerance,
    uint256 newTolerance
  );

  // =========== STORAGE =========== //

  IKrystalVault public krystalVault;
  uint256 public slippageToleranceDefault; // In basis points (10000 = 100%)

  uint256 public constant BASIS_POINTS = 10000;

  // =========== INITIALIZER =========== //

  /**
   * @notice Initializes the external yield vault
   * @param krystalVault_ The Krystal vault address
   * @param name_ The vault share token name
   * @param symbol_ The vault share token symbol
   * @param globalOwner_ The global owner contract address
   * @param globalPause_ The global pause contract address
   * @param globalAccessList_ The global restrict contract address
   * @param slippageToleranceDefault_ Initial slippage tolerance in basis points
   */
  function initialize(
    address krystalVault_,
    string calldata name_,
    string calldata symbol_,
    address globalOwner_,
    address globalPause_,
    address globalAccessList_,
    uint256 slippageToleranceDefault_
  ) external initializer {
    if (krystalVault_ == address(0)) revert ZeroAddress();

    // Get principal token from Krystal vault config
    (, , , address principalToken, , ) = IKrystalVault(krystalVault_)
      .getVaultConfig();
    if (principalToken == address(0)) revert ZeroAddress();

    __ERC4626_init(IERC20Upgradeable(principalToken));
    __ERC20_init(name_, symbol_);
    __AdministeredUpgradable_init(
      globalOwner_,
      globalPause_,
      globalAccessList_
    );

    krystalVault = IKrystalVault(krystalVault_);
    slippageToleranceDefault = slippageToleranceDefault_;

    // Approve Krystal vault to spend underlying asset
    IERC20Upgradeable(principalToken).approve(
      krystalVault_,
      type(uint256).max
    );
  }

  // =========== ERC-4626 OVERRIDES =========== //

  /**
   * @notice Returns the total assets managed by this vault in the Krystal vault
   * @return Total assets in underlying token
   */
  function totalAssets() public view override returns (uint256) {
    uint256 krystalShares = krystalVault.balanceOf(address(this));
    if (krystalShares == 0) return 0;

    uint256 krystalTotalSupply = krystalVault.totalSupply();
    if (krystalTotalSupply == 0) return 0;

    uint256 krystalTotalValue = krystalVault.getTotalValue();
    return
      krystalShares.mulDiv(krystalTotalValue, krystalTotalSupply);
  }

  /**
   * @notice Deposits assets into the Krystal vault (ERC4626 standard, uses default slippage)
   * @param assets Amount of underlying assets to deposit
   * @param receiver Address to receive the vault shares
   * @return shares Amount of vault shares minted
   */
  function deposit(
    uint256 assets,
    address receiver
  )
    public
    override
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 shares)
  {
    return _deposit(assets, receiver, slippageToleranceDefault);
  }

  /**
   * @notice Deposits assets with custom slippage tolerance
   * @param assets Amount of underlying assets to deposit
   * @param receiver Address to receive the vault shares
   * @param slippageTolerance_ Custom slippage tolerance in basis points
   * @return shares Amount of vault shares minted
   */
  function depositWithSlippage(
    uint256 assets,
    address receiver,
    uint256 slippageTolerance_
  )
    public
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 shares)
  {
    return _deposit(assets, receiver, slippageTolerance_);
  }

  /**
   * @notice Internal deposit implementation
   */
  function _deposit(
    uint256 assets,
    address receiver,
    uint256 slippageTolerance_
  ) internal returns (uint256 shares) {
    if (assets == 0) revert ZeroAmount();

    // Transfer assets from sender
    IERC20Upgradeable(asset()).safeTransferFrom(
      msg.sender,
      address(this),
      assets
    );

    // Calculate minimum shares with slippage
    uint256 expectedKrystalShares = _previewKrystalDeposit(assets);
    uint256 minKrystalShares = expectedKrystalShares.mulDiv(
      BASIS_POINTS - slippageTolerance_,
      BASIS_POINTS
    );

    // Deposit into Krystal vault
    uint256 krystalSharesBefore = krystalVault.balanceOf(
      address(this)
    );
    krystalVault.deposit(assets, minKrystalShares);
    uint256 krystalSharesReceived = krystalVault.balanceOf(
      address(this)
    ) - krystalSharesBefore;

    // Mint our shares 1:1 with Krystal shares received
    shares = krystalSharesReceived;
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @notice Mints vault shares by depositing assets
   * @param shares Amount of vault shares to mint
   * @param receiver Address to receive the vault shares
   * @return assets Amount of underlying assets deposited
   */
  function mint(
    uint256 shares,
    address receiver
  )
    public
    override
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 assets)
  {
    if (shares == 0) revert ZeroAmount();

    // Calculate assets needed for the shares
    assets = previewMint(shares);

    // Transfer assets from sender
    IERC20Upgradeable(asset()).safeTransferFrom(
      msg.sender,
      address(this),
      assets
    );

    // Deposit into Krystal vault
    uint256 krystalSharesBefore = krystalVault.balanceOf(
      address(this)
    );
    krystalVault.deposit(assets, 0); // No slippage check here, we check shares after
    uint256 krystalSharesReceived = krystalVault.balanceOf(
      address(this)
    ) - krystalSharesBefore;

    if (krystalSharesReceived < shares) revert InsufficientShares();

    // Mint exact shares requested
    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @notice Withdraws assets from the Krystal vault (ERC4626 standard, uses default slippage)
   * @param assets Amount of underlying assets to withdraw
   * @param receiver Address to receive the assets
   * @param owner_ Address that owns the vault shares
   * @return shares Amount of vault shares burned
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner_
  )
    public
    override
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 shares)
  {
    return
      _withdraw(assets, receiver, owner_, slippageToleranceDefault);
  }

  /**
   * @notice Withdraws assets with custom slippage tolerance
   * @param assets Amount of underlying assets to withdraw
   * @param receiver Address to receive the assets
   * @param owner_ Address that owns the vault shares
   * @param slippageTolerance_ Custom slippage tolerance in basis points
   * @return shares Amount of vault shares burned
   */
  function withdrawWithSlippage(
    uint256 assets,
    address receiver,
    address owner_,
    uint256 slippageTolerance_
  )
    public
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 shares)
  {
    return _withdraw(assets, receiver, owner_, slippageTolerance_);
  }

  /**
   * @notice Internal withdraw implementation
   */
  function _withdraw(
    uint256 assets,
    address receiver,
    address owner_,
    uint256 slippageTolerance_
  ) internal returns (uint256 shares) {
    if (assets == 0) revert ZeroAmount();

    // Calculate shares needed
    shares = previewWithdraw(assets);

    // Handle allowance if caller is not owner
    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    // Burn our shares
    _burn(owner_, shares);

    // Calculate minimum return with slippage
    uint256 minReturn = assets.mulDiv(
      BASIS_POINTS - slippageTolerance_,
      BASIS_POINTS
    );

    // Withdraw from Krystal vault
    uint256 returnedAssets = krystalVault.withdraw(
      shares,
      false,
      minReturn
    );

    // Transfer assets to receiver
    IERC20Upgradeable(asset()).safeTransfer(receiver, returnedAssets);

    emit Withdraw(
      msg.sender,
      receiver,
      owner_,
      returnedAssets,
      shares
    );
  }

  /**
   * @notice Redeems vault shares for underlying assets (ERC4626 standard, uses default slippage)
   * @param shares Amount of vault shares to redeem
   * @param receiver Address to receive the assets
   * @param owner_ Address that owns the vault shares
   * @return assets Amount of underlying assets received
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner_
  )
    public
    override
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 assets)
  {
    return
      _redeem(shares, receiver, owner_, slippageToleranceDefault);
  }

  /**
   * @notice Redeems vault shares with custom slippage tolerance
   * @param shares Amount of vault shares to redeem
   * @param receiver Address to receive the assets
   * @param owner_ Address that owns the vault shares
   * @param slippageTolerance_ Custom slippage tolerance in basis points
   * @return assets Amount of underlying assets received
   */
  function redeemWithSlippage(
    uint256 shares,
    address receiver,
    address owner_,
    uint256 slippageTolerance_
  )
    public
    whenNotPaused
    notRestricted(msg.sender)
    notRestricted(receiver)
    returns (uint256 assets)
  {
    return _redeem(shares, receiver, owner_, slippageTolerance_);
  }

  /**
   * @notice Internal redeem implementation
   */
  function _redeem(
    uint256 shares,
    address receiver,
    address owner_,
    uint256 slippageTolerance_
  ) internal returns (uint256 assets) {
    if (shares == 0) revert ZeroAmount();

    // Handle allowance if caller is not owner
    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    // Burn our shares
    _burn(owner_, shares);

    // Calculate expected assets and minimum with slippage
    uint256 expectedAssets = _previewKrystalRedeem(shares);
    uint256 minReturn = expectedAssets.mulDiv(
      BASIS_POINTS - slippageTolerance_,
      BASIS_POINTS
    );

    // Withdraw from Krystal vault
    assets = krystalVault.withdraw(shares, false, minReturn);

    // Transfer assets to receiver
    IERC20Upgradeable(asset()).safeTransfer(receiver, assets);

    emit Withdraw(msg.sender, receiver, owner_, assets, shares);
  }

  // =========== PREVIEW FUNCTIONS =========== //

  /**
   * @notice Preview the amount of shares for a deposit
   */
  function previewDeposit(
    uint256 assets
  ) public view override returns (uint256) {
    return _previewKrystalDeposit(assets);
  }

  /**
   * @notice Preview the amount of assets needed for minting shares
   */
  function previewMint(
    uint256 shares
  ) public view override returns (uint256) {
    uint256 krystalTotalSupply = krystalVault.totalSupply();
    uint256 krystalTotalValue = krystalVault.getTotalValue();
    uint256 sharesPrecision = krystalVault.SHARES_PRECISION();

    if (krystalTotalSupply == 0) {
      return shares / sharesPrecision;
    }
    return
      shares.mulDiv(
        krystalTotalValue,
        krystalTotalSupply,
        Math.Rounding.Up
      );
  }

  /**
   * @notice Preview the amount of shares needed for withdrawing assets
   */
  function previewWithdraw(
    uint256 assets
  ) public view override returns (uint256) {
    uint256 krystalTotalSupply = krystalVault.totalSupply();
    uint256 krystalTotalValue = krystalVault.getTotalValue();

    if (krystalTotalValue == 0) return 0;
    return
      assets.mulDiv(
        krystalTotalSupply,
        krystalTotalValue,
        Math.Rounding.Up
      );
  }

  /**
   * @notice Preview the amount of assets for redeeming shares
   */
  function previewRedeem(
    uint256 shares
  ) public view override returns (uint256) {
    return _previewKrystalRedeem(shares);
  }

  // =========== MAX FUNCTIONS =========== //

  /**
   * @notice Returns the maximum deposit amount
   */
  function maxDeposit(
    address
  ) public view override returns (uint256) {
    if (paused()) return 0;
    return type(uint256).max;
  }

  /**
   * @notice Returns the maximum mint amount
   */
  function maxMint(address) public view override returns (uint256) {
    if (paused()) return 0;
    return type(uint256).max;
  }

  /**
   * @notice Returns the maximum withdraw amount for an owner
   */
  function maxWithdraw(
    address owner_
  ) public view override returns (uint256) {
    if (paused()) return 0;
    return previewRedeem(balanceOf(owner_));
  }

  /**
   * @notice Returns the maximum redeem amount for an owner
   */
  function maxRedeem(
    address owner_
  ) public view override returns (uint256) {
    if (paused()) return 0;
    return balanceOf(owner_);
  }

  // =========== INTERNAL HELPERS =========== //

  /**
   * @notice Preview Krystal vault deposit
   */
  function _previewKrystalDeposit(
    uint256 assets
  ) internal view returns (uint256) {
    uint256 krystalTotalSupply = krystalVault.totalSupply();
    uint256 krystalTotalValue = krystalVault.getTotalValue();
    uint256 sharesPrecision = krystalVault.SHARES_PRECISION();

    if (krystalTotalSupply == 0) {
      return assets * sharesPrecision;
    }
    return assets.mulDiv(krystalTotalSupply, krystalTotalValue);
  }

  /**
   * @notice Preview Krystal vault withdraw (shares needed for assets)
   */
  function _previewKrystalWithdraw(
    uint256 assets
  ) internal view returns (uint256) {
    uint256 krystalTotalSupply = krystalVault.totalSupply();
    uint256 krystalTotalValue = krystalVault.getTotalValue();

    if (krystalTotalValue == 0) return 0;
    return
      assets.mulDiv(
        krystalTotalSupply,
        krystalTotalValue,
        Math.Rounding.Up
      );
  }

  /**
   * @notice Preview Krystal vault redeem (assets for shares)
   */
  function _previewKrystalRedeem(
    uint256 shares
  ) internal view returns (uint256) {
    uint256 krystalTotalSupply = krystalVault.totalSupply();
    uint256 krystalTotalValue = krystalVault.getTotalValue();

    if (krystalTotalSupply == 0) return 0;
    return shares.mulDiv(krystalTotalValue, krystalTotalSupply);
  }

  // =========== ADMIN FUNCTIONS =========== //

  /**
   * @notice Updates the Krystal vault address
   * @param newKrystalVault The new Krystal vault address
   */
  function setKrystalVault(
    address newKrystalVault
  ) external onlyOwner {
    if (newKrystalVault == address(0)) revert ZeroAddress();

    address oldVault = address(krystalVault);

    // Revoke approval from old vault
    IERC20Upgradeable(asset()).approve(oldVault, 0);

    // Set new vault and approve
    krystalVault = IKrystalVault(newKrystalVault);
    IERC20Upgradeable(asset()).approve(
      newKrystalVault,
      type(uint256).max
    );

    emit KrystalVaultUpdated(oldVault, newKrystalVault);
  }

  /**
   * @notice Updates the default slippage tolerance
   * @param newSlippageTolerance The new slippage tolerance in basis points
   */
  function setDefaultSlippageTolerance(
    uint256 newSlippageTolerance
  ) external onlyOwner {
    uint256 oldTolerance = slippageToleranceDefault;
    slippageToleranceDefault = newSlippageTolerance;
    emit SlippageToleranceUpdated(oldTolerance, newSlippageTolerance);
  }

  // =========== STORAGE GAP =========== //

  uint256[48] private __gap;
}
