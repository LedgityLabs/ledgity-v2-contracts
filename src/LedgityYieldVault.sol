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
import { IAaveLendingPoolV3 } from "./interfaces/IAaveLendingPoolV3.sol";

// ======== ERRORS ======== //
error ZeroAmount();
error InsufficientBalance(uint256 amount);
error BaseRateCannotBeLessThanOne();
error Paused();
error CannotWithdrawFromAnotherOwner();
error ZeroBaseRate();
error OnlyLiquidityManager();

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
  IERC20 public immutable underlying;
  // The token that represents the stake of a user in the protocol
  IERC20 public stakeToken;
  // The L-Token
  IERC20 public lToken;

  IAaveLendingPoolV3 public aaveLendingPool;
  // AAVE IBT or address(0) if there is not AAVE lending pool
  address public aToken;

  // The initial exchange rate of the shares token in Ray (27 decimals)
  uint256 public baseRate;
  uint256 public liquidityBufferRate;

  uint256 public managementFeeRate;
  uint256 public performanceFeeRate;
  uint256 public withdrawalFee;
  uint256 public fastWithdrawMinStake;

  address public liquidityManager;

  struct UserFeeStructure {
    bool hasFeeStructure;
    uint256 managementFee;
    uint256 performanceFee;
    uint256 withdrawalFee;
  }

  // ======== EVENTS ======== //

  event RateCheckpointUpdated(uint256 newRate, uint256 newAPR);
  event PausedSet(bool isPaused);

  // ======== INITIALIZE ======== //

  /**
   * @notice Initializes the Vault contract
   * @param globalOwner_ The address of the global owner
   * @param globalPause_ The address of the global pause controller
   * @param globalBlacklist_ The address of the global blacklist controller
   * @param underlying_ Address of the underlying
   * @param name_ Name for the shares token
   * @param symbol_ Symbol for the shares token
   */
  function initialize(
    address globalOwner_,
    address globalPause_,
    address globalBlacklist_,
    address liquidityManager_,
    address aaveLendingPool_,
    IERC20 underlying_,
    IERC20 stakeToken_,
    IERC20 lToken_,
    string memory name_,
    string memory symbol_
  ) public initializer {
    baseRate = RAY;

    __ERC20_init(name_, symbol_);
    __Base_init(globalOwner_, globalPause_, globalBlacklist_);

    underlying = underlying_;
    stakeToken = stakeToken_;
    lToken = lToken_;

    if (aaveLendingPool_ != address(0)) {
      aaveLendingPool = IAaveLendingPoolV3(aaveLendingPool_);
      aToken = aaveLendingPool
        .getReserveData(address(underlying))
        .aTokenAddress;

      IERC20(underlying).approve(
        address(aaveLendingPool),
        type(uint256).max
      );
    }

    // Initialize the first checkpoint
    snapshot();
  }

  // ======== MODIFIERS ======== //

  modifier onlyLiquidityManager() {
    if (msg.sender != liquidityManager) revert OnlyLiquidityManager();
    _;
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
    // uint256 timeElapsed = block.timestamp - lastCheckpoint.timestamp;
    uint256 timeElapsed = 0;

    // Calculate number of full days elapsed
    uint256 fullDays = timeElapsed / 1 days;
    uint256 remainingTime = timeElapsed % 1 days;

    // We want an APR we can use as a coefficient (100% = 1 RAY)
    // uint256 aprBaseOneRay = lastCheckpoint.apr / 100;
    uint256 aprBaseOneRay = 0;
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
   * @notice Returns the current index between aToken and underlying token
   * @return uint256 The current reward index in rays
   *
   * @dev A reward index of 1e27 means 1 aToken = 1 underlying token
   */
  function getBufferRewardIndex() public view returns (uint256) {
    return
      aaveLendingPool.getReserveNormalizedIncome(address(underlying));
  }

  /**
   * @notice Returns the current reward rate for the strategy
   * @return uint256 The reward rate in RAY
   *
   * @dev A reward rate of 1e28 means 100% APR
   */
  function getBufferRewardRate() external view returns (uint256) {
    return
      aaveLendingPool
        .getReserveData(address(underlying))
        .currentLiquidityRate;
  }

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

  // ======== INTERNAL HELPERS ======== //

  /**
   * @notice Deposits the specified amount of underlying assets into the Aave Lending Pool
   * @param amount The amount of underlying assets to deposit
   */
  function _depositBuffer(uint256 amount) private {
    /// @dev We already approved the contract in the initializer

    aaveLendingPool.deposit(
      address(underlying),
      amount,
      address(this),
      0
    );
  }

  /**
   * @notice Withdraws the specified amount of underlying assets from the Aave Lending Pool
   * @param amount The amount of underlying assets to withdraw
   * @param to The address to which the underlying assets will be transferred
   */
  function _withdrawBuffer(uint256 amount, address to) private {
    aaveLendingPool.withdraw(address(underlying), amount, to);
  }

  /**
   * @notice Internal function to handle depositing underlying
   * @param amount The amount of underlying to deposit
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
    snapshot();

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
   * @notice Internal function to handle withdraw tokens
   * @param sharesAmount The amount of shares tokens to withdraw
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
    snapshot();

    // Calculate underlying amount using updated rate
    amount_ = convertToAssets(sharesAmount);

    _burn(from, sharesAmount);
    underlying.transfer(to, amount_);

    emit Withdraw(from, to, from, amount_, sharesAmount);
  }

  // ======== WRITE FUNCTIONS ======== //

  /**
   * @notice Updates the rate checkpoint with current APR and rate
   * @dev This should be called whenever the APR changes
   */
  function snapshot() public {
    // Calculate the new base rate including all accumulated rewards
    baseRate = exchangeRate();
    // @todo @bw compute available fees
    // @todo @bw include buffer rewards
  }

  function migrateLToken(uint256 amount) public {}

  function requestWithdrawal(uint256 amount) public {}

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
    baseRate = newRate;
  }

  function depositToBuffer(
    uint256 amount
  ) public onlyLiquidityManager {
    // Transfer amount from fund wallet to contract
    underlying.safeTransferFrom(msg.sender, address(this), amount);

    if (aToken != address(0))
      _depositBuffer(underlying.balanceOf(address(this)));
  }

  function skimBuffer(uint256 amount) public onlyLiquidityManager {
    _withdrawBuffer(amount, msg.sender);
  }

  function processRequests(
    uint256[] calldata requestIds
  ) public onlyLiquidityManager {}

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
