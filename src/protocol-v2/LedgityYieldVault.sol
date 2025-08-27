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

/**
 * @title LedgityYieldVault
 * @notice An ERC-4626 vault token
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract LedgityYieldVault is
  BaseUpgradeable,
  CCIPToken,
  VaultLiquidityModule
{
  // ======== LIBS ======== //
  using SafeERC20 for IERC20;

  // ======== ERRORS ======== //

  /// @notice Thrown when an operation is attempted with zero amount
  error ZeroAmount();

  /// @notice Thrown when account has insufficient balance for operation
  /// @param amount The amount that was attempted to be used
  error InsufficientBalance(uint256 amount);

  /// @notice Thrown when base rate is set below minimum threshold
  error BaseRateCannotBeLessThanOne();

  /// @notice Thrown when attempting to withdraw from another user's account
  error CannotWithdrawFromAnotherOwner();

  /// @notice Thrown when base rate is set to zero
  error ZeroBaseRate();

  /// @notice Thrown when caller is not the authorized liquidity manager
  error OnlyLiquidityManager();

  /// @notice Thrown when withdrawal request doesn't include required gas fee
  error MissingWithdrawalRequestFee();

  /// @notice Thrown when referencing a non-existent withdrawal request
  error RequestNotFound();

  /// @notice Thrown when attempting to process an already processed request
  error RequestAlreadyProcessed();

  /// @notice Thrown when insufficient liquidity available for withdrawal processing
  error InsufficientLiquidity();

  // ======== STORAGE ======== //

  /// @notice The underlying ERC20 token that can be deposited into the vault
  IERC20 public underlying;

  /// @notice The legacy L-Token that can be migrated to vault shares
  IERC20 public lToken;

  /// @notice Address authorized to manage vault liquidity and process withdrawals
  address public liquidityManager;

  /// @notice Address that receives management and performance fees
  address payable public feeRecipient;

  /// @notice Whether the vault uses Aave as a buffer strategy for idle funds
  bool public hasBufferStrategy;

  /// @notice Aave interest bearing token address (aToken) or zero address if no Aave integration
  address public aToken;

  /// @notice Aave lending pool contract for buffer strategy operations
  IAaveLendingPoolV3 public aaveLendingPool;

  /// @notice Last recorded balance of buffer rewards to track new accruals
  uint256 public lastBufferRewardBalance;

  /// @notice Target percentage of total assets to maintain in liquidity buffer (in RATE_BASE)
  uint256 public liquidityBufferRate;

  /// @notice Token representing user's stake in the protocol for fee reductions
  IERC20 public stakeToken;

  /// @notice Fee reduction percentage for staking token holders (in RATE_BASE)
  uint256 public stakingFeeReduction;

  /// @notice Structure representing a queued withdrawal request
  /// @param user Address of the user who requested withdrawal
  /// @param assets Amount of underlying assets to withdraw
  /// @param timestamp When the withdrawal request was created
  /// @param processed Whether the request has been fulfilled
  struct WithdrawalRequest {
    address user;
    uint256 assets;
    uint256 timestamp;
    bool processed;
  }

  /// @notice Array storing all withdrawal requests in chronological order
  WithdrawalRequest[] public withdrawalRequests;

  // ======== EVENTS ======== //

  /// @notice Emitted when the vault's pause state is changed
  /// @param isPaused The new pause state
  event PausedSet(bool isPaused);

  /// @notice Emitted when a user requests a withdrawal
  /// @param requestId Unique identifier for the withdrawal request
  /// @param user Address of the user requesting withdrawal
  /// @param shares Amount of shares being withdrawn
  event WithdrawalRequested(
    uint256 indexed requestId,
    address indexed user,
    uint256 shares
  );

  /// @notice Emitted when a withdrawal request is processed and fulfilled
  /// @param requestId Unique identifier for the processed request
  /// @param user Address of the user receiving the withdrawal
  /// @param assets Amount of underlying assets transferred to user
  event WithdrawalProcessed(
    uint256 indexed requestId,
    address indexed user,
    uint256 assets
  );

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

      // Validate that aToken was properly retrieved
      if (aToken != address(0)) {
        hasBufferStrategy = true;
        IERC20(underlying).approve(
          address(aaveLendingPool),
          type(uint256).max
        );
      }
    }
  }

  // ======== MODIFIERS ======== //

  /// @notice Restricts function access to the authorized liquidity manager
  modifier onlyLiquidityManager() {
    if (msg.sender != liquidityManager) revert OnlyLiquidityManager();
    _;
  }

  // ======== OVERRIDES ======== //

  /// @notice Returns the number of decimals used for the vault token (18)
  /// @return The number of decimals
  function decimals()
    public
    view
    override(ERC20Upgradeable, ERC4626Upgradeable)
    returns (uint8)
  {
    return ERC4626Upgradeable.decimals();
  }

  /**
   * @notice Get the total underlying assets of the vault
   * @dev This includes buffer assets (in Aave if applicable) and assets in the liquidity manager
   * @inheritdoc ERC4626Upgradeable
   * @return Total underlying assets of the vault
   */
  function totalAssets()
    public
    view
    override(VaultLiquidityModule)
    returns (uint256)
  {
    return VaultLiquidityModule.totalAssets() + _bufferRewards();
  }

  // ======== VIEW ======== //

  /**
   * @notice Returns the additional APR contribution from the Aave buffer
   * @return uint256 The buffer APR contribution in RAY (1e27 = 100% APR)
   *
   * @dev Calculates (bufferAssets / totalAssets) * aaveAPR
   * This represents the additional yield from having assets in Aave buffer
   */
  function getBufferRewardRate() external view returns (uint256) {
    uint256 totalVaultAssets = totalAssets();

    // If no assets, return 0
    if (totalVaultAssets == 0) return 0;
    if (!hasBufferStrategy) return 0;

    // Get buffer assets and Aave APR
    uint256 bufferAssets = IERC20(aToken).balanceOf(address(this));
    uint256 aaveAPR = aaveLendingPool
      .getReserveData(address(underlying))
      .currentLiquidityRate;

    return (bufferAssets * aaveAPR) / totalVaultAssets;
  }

  /**
   * @notice Get withdrawal requests with optional filtering
   * @param onlyPending If true, only return non-processed requests
   * @param maxRequests Maximum number of requests to return (0 = no limit)
   * @return requests Array of withdrawal requests
   */
  function getWithdrawalRequests(
    bool onlyPending,
    uint256 maxRequests
  ) external view returns (WithdrawalRequest[] memory requests) {
    uint256 totalRequests = withdrawalRequests.length;
    if (totalRequests == 0) return requests;

    // Count valid requests
    uint256 validCount;
    for (uint256 i; i < totalRequests; i++) {
      if (!onlyPending || !withdrawalRequests[i].processed) {
        validCount++;
        if (maxRequests > 0 && validCount >= maxRequests) break;
      }
    }

    // Create result array
    requests = new WithdrawalRequest[](validCount);
    uint256 resultIndex;

    for (
      uint256 i;
      i < totalRequests && resultIndex < validCount;
      i++
    ) {
      if (!onlyPending || !withdrawalRequests[i].processed) {
        requests[resultIndex] = withdrawalRequests[i];
        resultIndex++;
      }
    }
  }

  /**
   * @notice Get withdrawal requests for a specific user
   * @param user The user address
   * @param onlyPending If true, only return non-processed requests
   * @return requestIds Array of request IDs for the user
   * @return requests Array of withdrawal requests for the user
   */
  function getUserWithdrawalRequests(
    address user,
    bool onlyPending
  )
    external
    view
    returns (
      uint256[] memory requestIds,
      WithdrawalRequest[] memory requests
    )
  {
    uint256 totalRequests = withdrawalRequests.length;

    // Count user requests
    uint256 userRequestCount;
    for (uint256 i; i < totalRequests; i++) {
      if (withdrawalRequests[i].user == user) {
        if (!onlyPending || !withdrawalRequests[i].processed) {
          userRequestCount++;
        }
      }
    }

    // Create result arrays
    requestIds = new uint256[](userRequestCount);
    requests = new WithdrawalRequest[](userRequestCount);
    uint256 resultIndex;

    for (
      uint256 i;
      i < totalRequests && resultIndex < userRequestCount;
      i++
    ) {
      if (withdrawalRequests[i].user == user) {
        if (!onlyPending || !withdrawalRequests[i].processed) {
          requestIds[resultIndex] = i;
          requests[resultIndex] = withdrawalRequests[i];
          resultIndex++;
        }
      }
    }
  }

  /**
   * @notice Get total number of withdrawal requests
   * @return Total number of requests created
   */
  function getWithdrawalRequestCount()
    external
    view
    returns (uint256)
  {
    return withdrawalRequests.length;
  }

  // ======== BUFFER INTERNAL HELPERS ======== //

  /// @dev Calculate new buffer rewards since last update
  /// @return Amount of new rewards accrued in buffer
  function _bufferRewards() private view returns (uint256) {
    if (!hasBufferStrategy) return 0;

    uint256 bufferAssets = IERC20(aToken).balanceOf(address(this));
    // Protect against underflow in case of Aave losses or slashing
    return
      bufferAssets > lastBufferRewardBalance
        ? bufferAssets - lastBufferRewardBalance
        : 0;
  }

  /// @dev Register and add buffer rewards to total assets
  function _registerBufferRewards() private {
    uint256 reward = _bufferRewards();
    if (reward == 0) return;

    _addAssets(reward);
    lastBufferRewardBalance += reward;
  }

  /**
   * @notice Deposits the specified amount of underlying assets into the Aave Lending Pool
   * @param amountAssets The amount of underlying assets to deposit
   */
  function _depositBuffer(uint256 amountAssets) private {
    /// @dev We already approved the contract in the initializer

    aaveLendingPool.deposit(
      address(underlying),
      amountAssets,
      address(this),
      0
    );

    lastBufferRewardBalance += amountAssets;
  }

  /**
   * @notice Withdraws the specified amount of underlying assets from the Aave Lending Pool
   * @param to The address to which the underlying assets will be transferred
   * @param amountAssets The amount of underlying assets to withdraw
   *
   * @dev In AAVE the aTokens are rebase tokens so underlying amount is the same as aToken amount
   */
  function _withdrawBuffer(address to, uint256 amountAssets) private {
    aaveLendingPool.withdraw(address(underlying), amountAssets, to);

    lastBufferRewardBalance -= amountAssets;
  }

  // ======== VAULT INTERNAL HELPERS ======== //

  /**
   * @notice Internal function to handle depositing underlying
   * @param caller The address that called the deposit function
   * @param receiver The address to receive the minted shares
   * @param assets The amount of underlying to deposit
   */
  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 /* shares */
  ) internal override(ERC4626Upgradeable) {
    if (assets == 0) revert ZeroAmount();

    // Register buffer rewards & take fees before processing
    harvestFees();

    // Apply capital deployment impact to amount of shares
    uint256 maturityImpact = _computeMaturityImpact(assets);
    uint256 netDeposit = assets - maturityImpact;
    uint256 netShares = convertToShares(netDeposit);

    _mint(receiver, netShares);
    _addAssets(netDeposit);

    // Calculate expected buffer balance after this deposit
    uint256 expectedBufferBalance = (totalAssets() *
      liquidityBufferRate) / RATE_BASE;

    uint256 currentBufferBalance = hasBufferStrategy
      ? IERC20(aToken).balanceOf(address(this))
      : IERC20(underlying).balanceOf(address(this));

    uint256 bufferAmount;
    uint256 vaultAmount;

    if (currentBufferBalance < expectedBufferBalance) {
      uint256 bufferDeficit = expectedBufferBalance -
        currentBufferBalance;

      // Use smaller amount between deposit amount and buffer deficit
      bufferAmount = assets < bufferDeficit ? assets : bufferDeficit;
      vaultAmount = assets - bufferAmount;
    } else {
      // Buffer is at or above target - send all to liquidity manager
      bufferAmount = 0;
      vaultAmount = assets;
    }

    underlying.transferFrom(caller, address(this), assets);

    // Execute the allocation
    if (0 < bufferAmount) {
      if (hasBufferStrategy) _depositBuffer(bufferAmount);
      /// @dev If no buffer strategy, assets stay in contract as underlying
    }
    if (0 < vaultAmount) {
      underlying.transfer(liquidityManager, vaultAmount);
    }

    emit Deposit(caller, receiver, assets, netShares);
  }

  /**
   * @notice Internal function to handle withdraw tokens
   * @param caller The address that called the withdraw function
   * @param receiver The address to receive the underlying
   * @param owner The owner of the shares tokens
   * @param shares The amount of shares tokens to withdraw
   */
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 /* assets */,
    uint256 shares
  ) internal override(ERC4626Upgradeable) {
    if (shares == 0) revert ZeroAmount();

    // Register buffer rewards & take fees before processing
    harvestFees();

    // Calculate underlying amount using updated rate
    uint256 withdrawalFee = _computeWithdrawalFee(shares, receiver);
    transferFrom(caller, feeRecipient, withdrawalFee);

    uint256 netShares = shares - withdrawalFee;
    uint256 netAssets = convertToAssets(netShares);

    _burn(caller, netShares);
    _withdrawAssets(netAssets);

    if (hasBufferStrategy) {
      _withdrawBuffer(receiver, netAssets);
    } else {
      underlying.transfer(receiver, netAssets);
    }

    emit Withdraw(caller, receiver, owner, netAssets, shares);
  }

  // ======== WRITE FUNCTIONS ======== //

  /// @notice Migrate legacy L-Tokens to vault shares at 1:1 rate
  /// @param amount Amount of L-Tokens to migrate
  /// @return shares Amount of vault shares minted
  /// @dev No maturity impact applied since capital remains deployed
  function migrateLToken(
    uint256 amount
  )
    public
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 shares)
  {
    if (amount == 0) revert ZeroAmount();

    // Register buffer rewards & take fees before processing
    harvestFees();

    lToken.safeTransferFrom(msg.sender, liquidityManager, amount);

    // Calculate shares amount using updated rate (treat L-Tokens same as underlying)
    /// @dev No maturity impact on migration since the capital stays deployed
    shares = convertToShares(amount);

    _mint(msg.sender, shares);
    _addAssets(amount);

    emit Deposit(msg.sender, msg.sender, amount, shares);
  }

  /**
   * @notice Deposit assets (underlying) and mint shares (shares tokens) to receiver
   * @param assets The amount of underlying to deposit
   * @param receiver The address to receive the minted shares
   * @return sharesPreview The number of shares minted
   */
  function deposit(
    uint256 assets,
    address receiver
  )
    public
    override(ERC4626Upgradeable)
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 sharesPreview)
  {
    sharesPreview = previewDeposit(assets);
    _deposit(msg.sender, receiver, assets, 0);
  }

  /**
   * @notice Mint shares (shares tokens) to receiver by depositing assets (underlying)
   * @param shares The number of shares to mint
   * @param receiver The address to receive the minted shares
   * @return assetsPreview The amount of underlying deposited
   */
  function mint(
    uint256 shares,
    address receiver
  )
    public
    override(ERC4626Upgradeable)
    whenNotPaused
    notBlacklisted(_msgSender())
    returns (uint256 assetsPreview)
  {
    assetsPreview = previewMint(shares);
    uint256 assets = convertToAssets(shares);
    _deposit(msg.sender, receiver, assets, 0);
  }

  /**
   * @notice Withdraw assets (underlying) by burning shares (shares tokens)
   * @param assets The amount of underlying to withdraw
   * @param receiver The address to receive the withdrawn underlying
   * @param owner The address of the owner of the shares
   * @return sharesPreview The number of shares burned
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  )
    public
    override(ERC4626Upgradeable)
    whenNotPaused
    notBlacklisted(owner)
    returns (uint256 sharesPreview)
  {
    sharesPreview = previewWithdraw(assets);
    uint256 shares = convertToShares(assets);
    _withdraw(msg.sender, receiver, owner, 0, shares);
  }

  /**
   * @notice Redeem shares (shares tokens) for assets (underlying)
   * @param shares The number of shares to redeem
   * @param receiver The address to receive the underlying
   * @param owner The address of the owner of the shares
   * @return assetsPreview The amount of underlying received
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  )
    public
    override(ERC4626Upgradeable)
    whenNotPaused
    notBlacklisted(owner)
    returns (uint256 assetsPreview)
  {
    assetsPreview = previewRedeem(shares);
    _withdraw(msg.sender, receiver, owner, 0, shares);
  }

  /// @notice Request a withdrawal that will be processed asynchronously
  /// @param shares Amount of vault shares to withdraw
  /// @dev Requires gas fee payment and burns shares immediately
  function requestWithdrawal(
    uint256 shares
  ) public payable whenNotPaused notBlacklisted(_msgSender()) {
    if (shares == 0) revert ZeroAmount();
    if (msg.value < withdrawalGasFee)
      revert MissingWithdrawalRequestFee();

    uint256 withdrawalFee = _computeWithdrawalFee(shares, msg.sender);
    transferFrom(msg.sender, feeRecipient, withdrawalFee);
    feeRecipient.transfer(address(this).balance);

    uint256 netShares = shares - withdrawalFee;
    uint256 netAssets = convertToAssets(netShares);

    // Create withdrawal request
    uint256 requestId = withdrawalRequests.length;
    withdrawalRequests.push(
      WithdrawalRequest({
        user: msg.sender,
        assets: netAssets,
        timestamp: block.timestamp,
        processed: false
      })
    );

    // Burn shares from user
    _burn(msg.sender, netShares);
    _withdrawAssets(netAssets);

    emit WithdrawalRequested(requestId, msg.sender, shares);
  }

  /// @notice Harvest buffer rewards and collect management/performance fees
  /// @dev Can be called by anyone to update vault state and collect fees
  function harvestFees() public {
    // Add buffer rewards
    _registerBufferRewards();
    // Take management and performance fees
    _takeFees(owner());
  }

  // ======== ADMIN ======== //

  /// @notice Deposit assets into the liquidity buffer
  /// @param amount Amount of underlying assets to deposit
  /// @dev Only callable by liquidity manager
  function depositToBuffer(
    uint256 amount
  ) public onlyLiquidityManager {
    // Transfer amount from fund wallet to contract
    underlying.safeTransferFrom(
      liquidityManager,
      address(this),
      amount
    );
    if (hasBufferStrategy) _depositBuffer(amount);
  }

  /// @notice Remove excess assets from the liquidity buffer
  /// @param amount Amount of assets to withdraw from buffer
  /// @dev Only callable by liquidity manager
  function skimBuffer(uint256 amount) public onlyLiquidityManager {
    _withdrawBuffer(liquidityManager, amount);
  }

  /// @notice Process queued withdrawal requests by providing liquidity
  /// @param requestIds Array of request IDs to process
  /// @param addedLiquidity Additional liquidity provided by liquidity manager
  /// @dev Only callable by liquidity manager, uses buffer + added liquidity
  function processRequests(
    uint256[] calldata requestIds,
    uint256 addedLiquidity
  ) public onlyLiquidityManager {
    if (0 < addedLiquidity) {
      underlying.safeTransferFrom(
        liquidityManager,
        address(this),
        addedLiquidity
      );
    }

    // Register buffer rewards & take fees before processing
    harvestFees();

    // Calculate total assets needed for selected requests
    uint256 assetsTotal;
    for (uint256 i; i < requestIds.length; i++) {
      WithdrawalRequest storage request = withdrawalRequests[
        requestIds[i]
      ];

      if (request.processed) revert RequestAlreadyProcessed();
      if (request.assets == 0) revert ZeroAmount();

      assetsTotal += request.assets;
    }

    // Check available liquidity (buffer + added liquidity)
    uint256 bufferBalance = hasBufferStrategy
      ? IERC20(aToken).balanceOf(address(this))
      : IERC20(underlying).balanceOf(address(this));

    uint256 availableLiquidity = bufferBalance + addedLiquidity;

    if (availableLiquidity < assetsTotal)
      revert InsufficientLiquidity();

    // Withdraw required assets from buffer if needed
    if (hasBufferStrategy) {
      uint256 neededFromBuffer = assetsTotal - availableLiquidity;
      _withdrawBuffer(address(this), neededFromBuffer);
    }

    // Process each request
    for (uint256 i; i < requestIds.length; i++) {
      uint256 requestId = requestIds[i];
      WithdrawalRequest storage request = withdrawalRequests[
        requestId
      ];

      // Transfer assets to user
      underlying.transfer(request.user, request.assets);
      // Mark as processed
      request.processed = true;

      emit WithdrawalProcessed(
        requestId,
        request.user,
        request.assets
      );
    }
  }

  /**
   * @notice Set new total assets to handle capital losses or gains
   * @param newTotalAssets The new total assets amount
   * @dev This function should be called when there are capital losses/gains that need to be recorded
   */
  function setTotalAssets(uint256 newTotalAssets) external onlyOwner {
    VaultLiquidityModule._setTotalAssets(newTotalAssets);
  }

  /**
   * @notice Updates the APR used for rate calculations
   * @param newAPR The new APR in RATE_BASE
   */
  function updateAPR(uint256 newAPR) external onlyOwner {
    VaultLiquidityModule._updateAPR(newAPR);
  }

  /**
   * @dev Update fee rates for the vault
   * @param managementRate_ The new management fee rate in RATE_BASE
   * @param performanceRate_ The new performance fee rate in RATE_BASE
   * @param withdrawalRate_ The new withdrawal fee rate in RATE_BASE
   */
  function updateFeeRates(
    uint256 managementRate_,
    uint256 performanceRate_,
    uint256 withdrawalRate_
  ) external onlyOwner {
    VaultLiquidityModule._updateFeeRates(
      managementRate_,
      performanceRate_,
      withdrawalRate_
    );
  }

  /**
   * @dev Set a custom fee structure for a specific account
   * @param account The account to set the custom fee structure for
   * @param withdrawalFee The custom withdrawal fee in RATE_BASE
   */
  function setCustomWithdrawalFee(
    address account,
    uint256 withdrawalFee
  ) external onlyOwner {
    VaultLiquidityModule._setCustomWithdrawalFee(
      account,
      withdrawalFee
    );
  }

  /**
   * @notice Update the deployment delay period
   * @param newDeploymentDelay The new deployment delay in days
   */
  function updateDeploymentDelay(
    uint256 newDeploymentDelay
  ) external onlyOwner {
    VaultLiquidityModule._updateDeploymentDelay(newDeploymentDelay);
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
