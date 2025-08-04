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

  // The initial exchange rate of the wrapped token in Ray (27 decimals)
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
   * @param underlying_ Address of the LToken to wrap
   * @param name_ Name for the wrapped token
   * @param symbol_ Symbol for the wrapped token
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
   * @notice Returns the number of decimals used by the wrapped token
   * @dev This is the same as the LToken decimals
   * @return decimals_ The number of decimals
   */
  function decimals() public view override returns (uint8) {
    return underlying.decimals();
  }

  /**
   * @notice Get the current exchange rate between wrapped tokens and LTokens
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

  /**
   * @notice Convert wrapped token amount to LToken amount
   * @param wrappedAmount The amount of wrapped tokens to convert
   * @return underlyingAmount_ The amount of LTokens that would be received
   */
  function toRebasingAmount(
    uint256 wrappedAmount
  ) public view returns (uint256) {
    return (wrappedAmount * exchangeRate()) / RAY;
  }

  /**
   * @notice Convert LToken amount to wrapped token amount
   * @param underlyingAmount The amount of LTokens to wrap
   * @return wrappedAmount_ The amount of wrapped tokens that would be received
   */
  function toWrappedAmount(
    uint256 underlyingAmount
  ) public view returns (uint256) {
    return (underlyingAmount * RAY) / exchangeRate();
  }

  /**
   * @notice Returns the total amount of LTokens held by this contract
   */
  function totalLTokenBalance() external view returns (uint256) {
    return underlying.balanceOf(address(this));
  }

  // ======== HELPERS ======== //

  /**
   * @notice Updates the rate checkpoint with current APR and rate
   * @dev This should be called whenever the APR changes
   */
  function updateRateCheckpoint() public {
    uint256 underlyingApr = uint256(underlying.getAPR());

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
   * @notice Internal function to handle wrapping LTokens
   * @param underlyingAmount The amount of LTokens to wrap
   * @param from The owner of the LTokens
   * @param to The recipient of the wrapped tokens
   * @return wrappedAmount_ The amount of wrapped tokens received
   */
  function _wrap(
    uint256 underlyingAmount,
    address from,
    address to
  ) internal returns (uint256 wrappedAmount_) {
    if (underlyingAmount == 0) revert WrapZeroAmount();
    if (underlying.balanceOf(from) < underlyingAmount) {
      revert InsufficientBalance(underlyingAmount);
    }

    // Update rate checkpoint before any operation that changes balances
    updateRateCheckpoint();

    // Calculate wrapped amount using updated rate
    wrappedAmount_ = toWrappedAmount(underlyingAmount);

    // We do avoid transfer for deposit & wrap functions
    if (from != address(this)) {
      underlying.transferFrom(from, address(this), underlyingAmount);
    }

    _mint(to, wrappedAmount_);

    emit Deposit(from, to, underlyingAmount, wrappedAmount_);
  }

  /**
   * @notice Internal function to handle unwrapping tokens
   * @param wrappedAmount The amount of wrapped tokens to unwrap
   * @param to The recipient of the LTokens
   * @param from The owner of the wrapped tokens
   * @return underlyingAmount_ The amount of LTokens received
   */
  function _unwrap(
    uint256 wrappedAmount,
    address from,
    address to
  ) internal returns (uint256 underlyingAmount_) {
    if (wrappedAmount == 0) revert WrapZeroAmount();
    if (wrappedAmount > balanceOf(from))
      revert InsufficientBalance(wrappedAmount);

    // Spend allowance if sender is not from
    if (msg.sender != from) {
      _spendAllowance(from, msg.sender, wrappedAmount);
    }

    // Update rate checkpoint before any operation that changes balances
    updateRateCheckpoint();

    // Calculate LToken amount using updated rate
    underlyingAmount_ = toRebasingAmount(wrappedAmount);

    _burn(from, wrappedAmount);
    underlying.transfer(to, underlyingAmount_);

    emit Withdraw(from, to, from, underlyingAmount_, wrappedAmount);
  }

  // ======== DEPOSIT AND WRAP ======== //

  /**
   * @notice Deposits underlying tokens into LToken and wraps the received LTokens
   * @param underlyingAmount The amount of underlying tokens to deposit
   */
  function depositAndWrap(
    uint256 underlyingAmount
  ) external whenNotPaused notBlacklisted(_msgSender()) {
    if (underlyingAmount == 0) revert WrapZeroAmount();

    // Get the underlying token from the LToken contract
    IERC20 underlying = IERC20(underlying.underlying());

    // Transfer underlying tokens from user to this contract
    underlying.safeTransferFrom(
      msg.sender,
      address(this),
      underlyingAmount
    );

    // Approve LToken to spend the underlying tokens
    underlying.safeApprove(address(underlying), underlyingAmount);

    // Deposit underlying tokens into LToken to get LTokens
    underlying.deposit(underlyingAmount, "");

    // Now wrap the received LTokens
    _wrap(underlyingAmount, address(this), msg.sender);
  }

  /**
   * @notice Deposits underlying tokens into LToken and wraps the received LTokens, sending them to a specified address
   * @param underlyingAmount The amount of underlying tokens to deposit
   * @param to The recipient of the wrapped tokens
   */
  function depositAndWrap(
    uint256 underlyingAmount,
    address to
  ) external whenNotPaused notBlacklisted(_msgSender()) {
    if (underlyingAmount == 0) revert WrapZeroAmount();

    // Get the underlying token from the LToken contract
    IERC20 underlying = IERC20(underlying.underlying());

    // Transfer underlying tokens from user to this contract
    underlying.safeTransferFrom(
      msg.sender,
      address(this),
      underlyingAmount
    );

    // Approve LToken to spend the underlying tokens
    underlying.safeApprove(address(underlying), underlyingAmount);

    // Deposit underlying tokens into LToken to get LTokens
    underlying.deposit(underlyingAmount, "");

    // Now wrap the received LTokens and send them to the specified address
    _wrap(underlyingAmount, address(this), to);
  }

  // ======== WRAP ======== //

  /**
   * @notice Wraps LTokens and receives wrapped tokens
   * @param underlyingAmount The amount of LTokens to wrap
   * @return wrappedAmount_ The amount of wrapped tokens received
   */
  function wrap(
    uint256 underlyingAmount
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 wrappedAmount_)
  {
    return _wrap(underlyingAmount, msg.sender, msg.sender);
  }

  /**
   * @notice Wraps LTokens and sends wrapped tokens to a specified address
   * @param underlyingAmount The amount of LTokens to wrap
   * @param to The recipient of the wrapped tokens
   * @return wrappedAmount_ The amount of wrapped tokens received
   */
  function wrap(
    uint256 underlyingAmount,
    address to
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 wrappedAmount_)
  {
    return _wrap(underlyingAmount, msg.sender, to);
  }

  // ======== UNWRAP ======== //

  /**
   * @notice Unwraps tokens back to LTokens
   * @param wrappedAmount The amount of wrapped tokens to unwrap
   * @return underlyingAmount_ The amount of LTokens received
   */
  function unwrap(
    uint256 wrappedAmount
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 underlyingAmount_)
  {
    return _unwrap(wrappedAmount, msg.sender, msg.sender);
  }

  /**
   * @notice Unwraps tokens and sends LTokens to a specified address
   * @param wrappedAmount The amount of wrapped tokens to unwrap
   * @param to The recipient of the LTokens
   * @return underlyingAmount_ The amount of LTokens received
   */
  function unwrap(
    uint256 wrappedAmount,
    address to
  )
    external
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 underlyingAmount_)
  {
    return _unwrap(wrappedAmount, msg.sender, to);
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
   * @notice Converts an amount of assets (underlying) to shares (wrapped tokens)
   * @param assets The amount of underlying assets to convert
   * @return shares The amount of shares (wrapped tokens) equivalent to the given assets
   */
  function convertToShares(
    uint256 assets
  ) public view returns (uint256 shares) {
    shares = toWrappedAmount(assets);
  }

  /**
   * @notice Converts an amount of shares (wrapped tokens) to assets (underlying)
   * @param shares The amount of shares (wrapped tokens) to convert
   * @return assets The amount of underlying assets equivalent to the given shares
   */
  function convertToAssets(
    uint256 shares
  ) public view returns (uint256 assets) {
    assets = toRebasingAmount(shares);
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
   * @notice Deposit assets (underlying) and mint shares (wrapped tokens) to receiver
   * @param assets The amount of LTokens to deposit
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
    shares = _wrap(assets, msg.sender, receiver);
  }

  /**
   * @notice Mint shares (wrapped tokens) to receiver by depositing assets (underlying)
   * @param shares The number of shares to mint
   * @param receiver The address to receive the minted shares
   * @return assets The amount of LTokens deposited
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
    _wrap(assets, msg.sender, receiver);
  }

  /**
   * @notice Withdraw assets (underlying) by burning shares (wrapped tokens)
   * @param assets The amount of LTokens to withdraw
   * @param receiver The address to receive the withdrawn LTokens
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
    _unwrap(shares, owner, receiver);
  }

  /**
   * @notice Redeem shares (wrapped tokens) for assets (underlying)
   * @param shares The number of shares to redeem
   * @param receiver The address to receive the LTokens
   * @param owner The address of the owner of the shares
   * @return assets The amount of LTokens received
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
    assets = _unwrap(shares, owner, receiver);
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
