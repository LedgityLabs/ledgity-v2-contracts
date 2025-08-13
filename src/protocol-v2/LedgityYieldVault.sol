// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { CCIPToken } from "../misc/CCIPToken.sol";
import { GlobalOwnableUpgradeable } from "../abstracts/GlobalOwnableUpgradeable.sol";
import { GlobalPausableUpgradeable } from "../abstracts/GlobalPausableUpgradeable.sol";
import { GlobalRestrictableUpgradeable } from "../abstracts/GlobalRestrictableUpgradeable.sol";
import { RecoverableUpgradeable } from "../abstracts/RecoverableUpgradeable.sol";
import { BaseUpgradeable } from "../abstracts/base/BaseUpgradeable.sol";
import { VaultLiquidityModule } from "./VaultLiquidityModule.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IAaveLendingPoolV3 } from "../interfaces/IAaveLendingPoolV3.sol";

// ======== LIBS ======== //
using SafeERC20 for IERC20;

// ======== ERRORS ======== //
error ZeroAmount();
error InsufficientBalance(uint256 amount);
error BaseRateCannotBeLessThanOne();
error Paused();
error CannotWithdrawFromAnotherOwner();
error ZeroBaseRate();
error OnlyLiquidityManager();
error MissingWithdrawalRequestFee();

/**
 * @title LedgityYieldVault
 * @notice An ERC-4626 vault token
 */
contract LedgityYieldVault is
  BaseUpgradeable,
  CCIPToken,
  VaultLiquidityModule
{
  // ======== STORAGE ======== //

  // The underlying token that may be deposited
  IERC20 public underlying;
  // The token that represents the stake of an account in the protocol
  IERC20 public stakeToken;
  // The L-Token
  IERC20 public lToken;

  address public liquidityManager;

  IAaveLendingPoolV3 public aaveLendingPool;
  // AAVE IBT or address(0) if there is not AAVE lending pool
  address public aToken;
  uint256 public lastBufferRewardBalance;

  uint256 public liquidityBufferRate;
  uint256 public fastWithdrawMinStake;

  // ======== EVENTS ======== //

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
    string memory symbol_,
    VaultInitParams calldata initParams
  ) public initializer {
    __ERC4626_init(IERC20Upgradeable(address(underlying_)));
    __ERC20_init(name_, symbol_);
    __Base_init(globalOwner_, globalPause_, globalBlacklist_);

    // Initialize the liquidity module with APR and fee rates
    __VaultLiquidityModule_init(initParams, address(underlying_));

    liquidityManager = liquidityManager_;
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
  }

  // ======== MODIFIERS ======== //

  modifier onlyLiquidityManager() {
    if (msg.sender != liquidityManager) revert OnlyLiquidityManager();
    _;
  }

  // ======== VIEW ======== //

  function decimals()
    public
    view
    override(ERC20Upgradeable, ERC4626Upgradeable)
    returns (uint8)
  {
    return ERC4626Upgradeable.decimals();
  }

  // ======== VIEW ======== //

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
   * @notice Get the total underlying assets of the vault
   * @dev This includes buffer assets (in Aave if applicable) and assets in the liquidity manager
   * @inheritdoc IERC4626
   * @return Total underlying assets of the vault
   */
  function totalAssets() public view override returns (uint256) {
    uint256 bufferAssets = 0;

    // Add buffer assets
    if (aToken != address(0)) {
      // If using Aave, get the aToken balance
      bufferAssets = IERC20(aToken).balanceOf(address(this));
    } else {
      // Otherwise, just use the underlying balance in this contract
      bufferAssets = underlying.balanceOf(address(this));
    }

    // Return total of buffer assets and assets tracked by VaultLiquidityModule
    return bufferAssets + totalAssets();
  }

  // ======== INTERNAL HELPERS ======== //

  function _registerBufferRewards() private {
    if (aToken == address(0)) return;

    uint256 bufferAssets = IERC20(aToken).balanceOf(address(this));

    if (bufferAssets == lastBufferRewardBalance) return;

    uint256 reward = bufferAssets - lastBufferRewardBalance;

    _queueDeposit(reward);
    lastBufferRewardBalance = bufferAssets;
  }

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
    if (amount == 0) revert ZeroAmount();

    // Add buffer rewards
    _registerBufferRewards();
    // Take management and performance fees
    _takeFees(owner());

    // Calculate shares amount using updated rate
    // Apply management fee on rate
    sharesAmount_ = convertToShares(amount);

    _mint(to, sharesAmount_);
    _queueDeposit(amount);

    underlying.transferFrom(from, address(this), amount);

    uint256 bufferAmount = (amount * liquidityBufferRate) / RATE_BASE;
    uint256 vaultAmount = amount - bufferAmount;

    if (aToken != address(0)) _depositBuffer(bufferAmount);
    underlying.transfer(liquidityManager, vaultAmount);

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
    if (sharesAmount == 0) revert ZeroAmount();

    // Add buffer rewards
    _registerBufferRewards();
    // Take management and prformance fees
    _takeFees(owner());

    // Calculate underlying amount using updated rate
    amount_ = convertToAssets(sharesAmount);

    _burn(from, sharesAmount);
    _withdrawAssets(amount_);

    // Calculate withdrawal fee if applicable
    uint256 withdrawalFee = _calculateWithdrawalFee(amount_, from);
    if (withdrawalFee > 0) {
      // Transfer withdrawal fee to liquidity manager
      amount_ = amount_ - withdrawalFee;
      underlying.transfer(liquidityManager, withdrawalFee);
    }

    underlying.transfer(to, amount_);

    emit Withdraw(from, to, from, amount_, sharesAmount);
  }

  // ======== WRITE FUNCTIONS ======== //

  function migrateLToken(uint256 amount) public {}

  function requestWithdrawal(uint256 amount) public {
    if (msg.value < withdrawalGasFee)
      revert MissingWithdrawalRequestFee();
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
    public
    override
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
    public
    override
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
    public
    override
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
    public
    override
    whenNotPaused
    notBlacklisted(owner)
    returns (uint256 assets)
  {
    assets = _withdraw(shares, owner, receiver);
  }

  // ======== ADMIN ======== //

  function harvestFees() external {
    // Add buffer rewards
    _registerBufferRewards();

    // Take management and performance fees
    _takeFees(owner());

    // Register fund revenue
    _registerFundRevenue();
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
    uint256[] calldata requestIds,
    uint256 addedLiquidity
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
