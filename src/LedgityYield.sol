// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { CCIPToken } from "./misc/CCIPToken.sol";
import { GlobalOwnableUpgradeable } from "./abstracts/GlobalOwnableUpgradeable.sol";
import { GlobalPausableUpgradeable } from "./abstracts/GlobalPausableUpgradeable.sol";
import { GlobalRestrictableUpgradeable } from "./abstracts/GlobalRestrictableUpgradeable.sol";
import { RecoverableUpgradeable } from "./abstracts/RecoverableUpgradeable.sol";
import { BaseUpgradeable } from "./abstracts/base/BaseUpgradeable.sol";
//
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

// Interfaces
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ======== ERRORS ======== //
error WrapZeroAmount();
error InsufficientBalance(uint256 amount);
error BaseRateCannotBeLessThanOne();
error WrapUnwrapPaused();
error CannotWithdrawFromAnotherOwner();
error ZeroBaseRate();

/**
 * @title LedgityYield
 * @notice An ERC-4626 vault token
 */
contract LedgityYield is
  ERC20Upgradeable,
  BaseUpgradeable,
  CCIPToken,
  IERC4626
{
  // ======== LIBS ======== //
  using SafeERC20 for IERC20;

  // ======== STORAGE ======== //
  uint256 public constant RAY = 1e27;

  // The underlying token that may be deposited
  IERC20 public underlying;

  // The initial exchange rate of the shares token in Ray (27 decimals)
  uint256 public baseRate;

  // Checkpoint for rate calculations
  struct LastRateCheckpoint {
    uint256 timestamp; // When checkpoint was created
    uint256 apr; // The APR at checkpoint in base 100 RAY (1% = 1 RAY)
  }

  // Last recorded checkpoint
  LastRateCheckpoint public lastCheckpoint;

  // ======== EVENTS ======== //

  event RateCheckpointUpdated(uint256 newRate, uint256 newAPR);
  event WrapUnwrapPausedSet(bool isPaused);

  // ======== INITIALIZE ======== //

  /**
   * @notice Initializes the WrappedLToken contract
   * @param globalOwner_ The address of the global owner
   * @param globalPause_ The address of the global pause controller
   * @param globalBlacklist_ The address of the global blacklist controller
   * @param underlying_ Address of the underlying to wrap
   * @param name_ Name for the shares token
   * @param symbol_ Symbol for the shares token
   */
  function initialize(
    address globalOwner_,
    address globalPause_,
    address globalBlacklist_,
    IERC20 underlying_,
    string memory name_,
    string memory symbol_
  ) public initializer {
    baseRate = RAY;

    __ERC20_init(name_, symbol_);
    __Base_init(globalOwner_, globalPause_, globalBlacklist_);

    underlying = underlying_;

    // Initialize the first checkpoint
    updateRateCheckpoint();
  }

  // ======== VIEW ======== //

  /**
   * @notice Get the current exchange rate between shares tokens and underlying
   * @return compoundedRate The exchange rate in ray (27 decimals)
   */
  function exchangeRate()
    public
    view
    returns (uint256 compoundedRate)
  {
    compoundedRate = baseRate;

    // Time elapsed since last checkpoint
    uint256 timeElapsed = block.timestamp - lastCheckpoint.timestamp;

    // Calculate number of full days elapsed
    uint256 fullDays = timeElapsed / 1 days;
    uint256 remainingTime = timeElapsed % 1 days;

    // We want an APR we can use as a coefficient (100% = 1 RAY)
    uint256 aprBaseOneRay = lastCheckpoint.apr / 100;
    // Daily rate = APR / 365
    uint256 dailyRatio = aprBaseOneRay / 365;

    // Apply daily compounding for full days
    for (uint256 i = 0; i < fullDays; i++) {
      compoundedRate = (compoundedRate * (RAY + dailyRatio)) / RAY;
    }

    // Add remaining time linearly without compounding
    if (remainingTime > 0) {
      // Calculate the partial day ratio: (APR * remainingTime) / (365 days)
      uint256 remainingRatio = (aprBaseOneRay * remainingTime) /
        (365 days);
      compoundedRate =
        (compoundedRate * (RAY + remainingRatio)) /
        RAY;
    }

    return compoundedRate;
  }

  // ======== HELPERS ======== //

  /**
   * @notice Updates the rate checkpoint with current APR and rate
   * @dev This should be called whenever the APR changes
   */
  function updateRateCheckpoint() public {
    uint256 underlyingApr = 0;

    // Only update if APR changed
    if (underlyingApr != lastCheckpoint.apr) {
      // Calculate the new base rate including all accumulated rewards
      baseRate = exchangeRate();

      uint256 apr = (underlyingApr * RAY) / 1000;

      lastCheckpoint = LastRateCheckpoint({
        timestamp: block.timestamp,
        apr: apr
      });

      emit RateCheckpointUpdated(baseRate, apr);
    }
  }

  // ======== INTERNAL ======== //

  /**
   * @notice Internal function to handle wrapping underlying
   * @param amount The amount of underlying to wrap
   * @param from The owner of the underlying
   * @param to The recipient of the shares tokens
   * @return sharesAmount_ The amount of shares tokens received
   */
  function _deposit(
    uint256 amount,
    address from,
    address to
  ) internal returns (uint256 sharesAmount_) {
    if (amount == 0) revert WrapZeroAmount();
    if (underlying.balanceOf(from) < amount) {
      revert InsufficientBalance(amount);
    }

    // Update rate checkpoint before any operation that changes balances
    updateRateCheckpoint();

    // Calculate shares amount using updated rate
    sharesAmount_ = convertToShares(amount);

    // We do avoid transfer for deposit & wrap functions
    if (from != address(this)) {
      underlying.transferFrom(from, address(this), amount);
    }

    _mint(to, sharesAmount_);

    emit Deposit(from, to, amount, sharesAmount_);
  }

  /**
   * @notice Internal function to handle unwrapping tokens
   * @param sharesAmount The amount of shares tokens to unwrap
   * @param to The recipient of the underlying
   * @param from The owner of the shares tokens
   * @return amount_ The amount of underlying received
   */
  function _withdraw(
    uint256 sharesAmount,
    address from,
    address to
  ) internal returns (uint256 amount_) {
    if (sharesAmount == 0) revert WrapZeroAmount();
    if (sharesAmount > balanceOf(from))
      revert InsufficientBalance(sharesAmount);

    // Spend allowance if sender is not from
    if (msg.sender != from) {
      _spendAllowance(from, msg.sender, sharesAmount);
    }

    // Update rate checkpoint before any operation that changes balances
    updateRateCheckpoint();

    // Calculate underlying amount using updated rate
    amount_ = convertToAssets(sharesAmount);

    _burn(from, sharesAmount);
    underlying.transfer(to, amount_);

    emit Withdraw(from, to, from, amount_, sharesAmount);
  }

  // ======== ERC-4626 ======== //

  /**
   * @notice Returns the address of the underlying asset (ERC20) for the vault
   * @return assetTokenAddress The address of the underlying ERC20 asset
   */
  function asset() public view returns (address assetTokenAddress) {
    return address(underlying);
  }

  /**
   * @notice Returns the total amount of the underlying asset managed by the vault
   * @return totalManagedAssets The total amount of the underlying asset held by the vault
   */
  function totalAssets()
    public
    view
    returns (uint256 totalManagedAssets)
  {
    return underlying.balanceOf(address(this));
  }

  /**
   * @notice Converts an amount of assets (underlying) to shares (shares tokens)
   * @param assets The amount of underlying assets to convert
   * @return shares The amount of shares (shares tokens) equivalent to the given assets
   */
  function convertToShares(
    uint256 assets
  ) public view returns (uint256 shares) {
    shares = (assets * RAY) / exchangeRate();
  }

  /**
   * @notice Converts an amount of shares (shares tokens) to assets (underlying)
   * @param shares The amount of shares (shares tokens) to convert
   * @return assets The amount of underlying assets equivalent to the given shares
   */
  function convertToAssets(
    uint256 shares
  ) public view returns (uint256 assets) {
    assets = (shares * exchangeRate()) / RAY;
  }

  /**
   * @notice Maximum amount of assets that can be deposited for receiver
   * @return maxAssets The maximum assets that can be deposited for the receiver
   */
  function maxDeposit(
    address /* receiver */
  ) public pure returns (uint256 maxAssets) {
    maxAssets = type(uint256).max;
  }

  /**
   * @notice Maximum number of shares that can be minted for receiver
   * @return maxShares The maximum number of shares that can be minted for the receiver
   */
  function maxMint(
    address /* receiver */
  ) public pure returns (uint256 maxShares) {
    maxShares = type(uint256).max;
  }

  /**
   * @notice Maximum amount of assets withdrawable by owner
   * @param owner The address for which the withdrawal limit is queried
   * @return maxAssets The maximum amount of assets withdrawable by the owner
   */
  function maxWithdraw(
    address owner
  ) public view returns (uint256 maxAssets) {
    maxAssets = convertToAssets(balanceOf(owner));
  }

  /**
   * @notice Maximum number of shares redeemable by owner
   * @param owner The address for which the redeem limit is queried
   * @return maxShares The maximum number of shares redeemable by the owner
   */
  function maxRedeem(
    address owner
  ) public view returns (uint256 maxShares) {
    maxShares = balanceOf(owner);
  }

  /**
   * @notice Preview the number of shares minted for a deposit of assets
   * @param assets The amount of underlying assets to deposit
   * @return shares The number of shares that would be minted
   */
  function previewDeposit(
    uint256 assets
  ) public view returns (uint256 shares) {
    shares = convertToShares(assets);
  }

  /**
   * @notice Preview the number of assets needed to mint the given shares
   * @param shares The number of shares to mint
   * @return assets The amount of underlying assets required
   */
  function previewMint(
    uint256 shares
  ) public view returns (uint256 assets) {
    assets = convertToAssets(shares);
  }

  /**
   * @notice Preview the number of shares burned for withdrawing assets
   * @param assets The amount of underlying assets to withdraw
   * @return shares The number of shares that would be burned
   */
  function previewWithdraw(
    uint256 assets
  ) public view returns (uint256 shares) {
    shares = convertToShares(assets);
  }

  /**
   * @notice Preview the number of assets received for redeeming shares
   * @param shares The number of shares to redeem
   * @return assets The amount of underlying assets received
   */
  function previewRedeem(
    uint256 shares
  ) public view returns (uint256 assets) {
    assets = convertToAssets(shares);
  }

  /**
   * @notice Deposit assets (underlying) and mint shares (shares tokens) to receiver
   * @param assets The amount of underlying to deposit
   * @param receiver The address to receive the minted shares
   * @return shares The number of shares minted
   */
  function deposit(
    uint256 assets,
    address receiver
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 shares)
  {
    shares = _deposit(assets, msg.sender, receiver);
  }

  /**
   * @notice Mint shares (shares tokens) to receiver by depositing assets (underlying)
   * @param shares The number of shares to mint
   * @param receiver The address to receive the minted shares
   * @return assets The amount of underlying deposited
   */
  function mint(
    uint256 shares,
    address receiver
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 assets)
  {
    assets = convertToAssets(shares);
    _deposit(assets, msg.sender, receiver);
  }

  /**
   * @notice Withdraw assets (underlying) by burning shares (shares tokens)
   * @param assets The amount of underlying to withdraw
   * @param receiver The address to receive the withdrawn underlying
   * @param owner The address of the owner of the shares
   * @return shares The number of shares burned
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  )
    external
    whenNotPaused
    notBlacklisted(owner)
    returns (uint256 shares)
  {
    shares = convertToShares(assets);
    _withdraw(shares, owner, receiver);
  }

  /**
   * @notice Redeem shares (shares tokens) for assets (underlying)
   * @param shares The number of shares to redeem
   * @param receiver The address to receive the underlying
   * @param owner The address of the owner of the shares
   * @return assets The amount of underlying received
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  )
    external
    whenNotPaused
    notBlacklisted(owner)
    returns (uint256 assets)
  {
    assets = _withdraw(shares, owner, receiver);
  }

  // ======== ADMIN ======== //

  /**
   * @notice Updates the base rate
   * @param newRate The new base rate in ray (27 decimals)
   */
  function updateBaseRate(uint256 newRate) public onlyOwner {
    if (newRate < RAY) revert BaseRateCannotBeLessThanOne();
    baseRate = newRate;
  }

  /**
   * @notice Recovers a specified amount of a given token address.
   * @dev This override of RecoverableUpgradeable.recoverERC20() prevents the recovered
   * token from being the underlying token.
   * @inheritdoc RecoverableUpgradeable
   */
  function recoverERC20(
    address tokenAddress,
    uint256 amount
  ) public override onlyOwner {
    if (tokenAddress == address(0)) {
      payable(msg.sender).transfer(amount);
    } else {
      super.recoverERC20(tokenAddress, amount);
    }
  }
}
