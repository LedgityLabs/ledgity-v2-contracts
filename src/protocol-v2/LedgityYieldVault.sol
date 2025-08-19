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
  error ZeroAmount();
  error InsufficientBalance(uint256 amount);
  error BaseRateCannotBeLessThanOne();
  error CannotWithdrawFromAnotherOwner();
  error ZeroBaseRate();
  error OnlyLiquidityManager();
  error MissingWithdrawalRequestFee();
  error RequestNotFound();
  error RequestAlreadyProcessed();
  error InsufficientLiquidity();

  // ======== STORAGE ======== //

  // The underlying token that may be deposited
  IERC20 public underlying;
  // The L-Token
  IERC20 public lToken;

  address public liquidityManager;
  address payable public feeRecipient;

  bool public hasBufferStrategy;
  // AAVE IBT or address(0) if there is not AAVE lending pool
  address public aToken;
  IAaveLendingPoolV3 public aaveLendingPool;

  uint256 public lastBufferRewardBalance;
  /// @dev The amount of assets held in the liquidity buffer expressed in RATE_BASE
  uint256 public liquidityBufferRate;

  // The token that represents the stake of an account in the protocol
  IERC20 public stakeToken;
  uint256 public stakingFeeReduction;

  // Withdrawal queue
  struct WithdrawalRequest {
    address user;
    uint256 assets;
    uint256 timestamp;
    bool processed;
  }

  WithdrawalRequest[] public withdrawalRequests;

  // ======== EVENTS ======== //

  event PausedSet(bool isPaused);
  event WithdrawalRequested(
    uint256 indexed requestId,
    address indexed user,
    uint256 shares
  );
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
      hasBufferStrategy = true;
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

  // ======== OVERRIDES ======== //

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
   * @inheritdoc IERC4626
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

  function _bufferRewards() private returns (uint256) {
    if (!hasBufferStrategy) return 0;

    uint256 bufferAssets = IERC20(aToken).balanceOf(address(this));
    return bufferAssets - lastBufferRewardBalance;
  }

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
   * @param amountAssets The amount of underlying assets to withdraw
   * @param to The address to which the underlying assets will be transferred
   *
   * @dev In AAVE the aTokens are rebase tokens so underlying amount is the same as aToken amount
   */
  function _withdrawBuffer(uint256 amountAssets, address to) private {
    aaveLendingPool.withdraw(address(underlying), amountAssets, to);

    lastBufferRewardBalance -= amountAssets;
  }

  // ======== VAULT INTERNAL HELPERS ======== //

  /**
   * @notice Internal function to handle depositing underlying
   * @param amount The amount of underlying to deposit
   * @param from The owner of the underlying
   * @param to The recipient of the shares tokens
   * @return netShares The amount of shares tokens received
   */
  function _deposit(
    uint256 amount,
    address from,
    address to
  ) internal returns (uint256 netShares) {
    if (amount == 0) revert ZeroAmount();

    // Register buffer rewards & take fees before processing
    harvestFees();

    // Apply capital deployment impact to amount of shares
    uint256 maturityImpact = _computeMaturityImpact(amount);
    uint256 netDeposit = amount - maturityImpact;
    netShares = convertToShares(netDeposit);

    _mint(to, netShares);
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
      bufferAmount = amount < bufferDeficit ? amount : bufferDeficit;
      vaultAmount = amount - bufferAmount;
    } else {
      // Buffer is at or above target - send all to liquidity manager
      bufferAmount = 0;
      vaultAmount = amount;
    }

    underlying.transferFrom(from, address(this), amount);

    // Execute the allocation
    if (0 < bufferAmount) {
      if (hasBufferStrategy) _depositBuffer(bufferAmount);
      /// @dev If no buffer strategy, assets stay in contract as underlying
    }
    if (0 < vaultAmount) {
      underlying.transfer(liquidityManager, vaultAmount);
    }

    emit Deposit(from, to, amount, netShares);
  }

  /**
   * @notice Internal function to handle withdraw tokens
   * @param shares The amount of shares tokens to withdraw
   * @param to The recipient of the underlying
   * @param from The owner of the shares tokens
   * @return netAssets The amount of underlying received
   */
  function _withdraw(
    uint256 shares,
    address from,
    address to
  ) internal returns (uint256 netAssets) {
    if (shares == 0) revert ZeroAmount();

    // Register buffer rewards & take fees before processing
    harvestFees();

    // Calculate underlying amount using updated rate
    uint256 withdrawalFee = _computeWithdrawalFee(shares, msg.sender);
    transferFrom(msg.sender, feeRecipient, withdrawalFee);

    uint256 netShares = shares - withdrawalFee;
    netAssets = convertToAssets(netShares);

    _burn(from, netShares);
    _withdrawAssets(netAssets);

    if (hasBufferStrategy) {
      _withdrawBuffer(netAssets, to);
    } else {
      underlying.transfer(to, netAssets);
    }

    emit Withdraw(from, to, from, netAssets, shares);
  }

  // ======== WRITE FUNCTIONS ======== //

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

  function harvestFees() public {
    // Add buffer rewards
    _registerBufferRewards();
    // Take management and performance fees
    _takeFees(owner());
  }

  // ======== ADMIN ======== //

  function depositToBuffer(
    uint256 amount
  ) public onlyLiquidityManager {
    // Transfer amount from fund wallet to contract
    underlying.safeTransferFrom(msg.sender, address(this), amount);

    if (hasBufferStrategy)
      _depositBuffer(underlying.balanceOf(address(this)));
  }

  function skimBuffer(uint256 amount) public onlyLiquidityManager {
    _withdrawBuffer(amount, msg.sender);
  }

  function processRequests(
    uint256[] calldata requestIds,
    uint256 addedLiquidity
  ) public onlyLiquidityManager {
    if (0 < addedLiquidity) {
      underlying.safeTransferFrom(
        msg.sender,
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
      _withdrawBuffer(neededFromBuffer, address(this));
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
