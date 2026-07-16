// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { CCIPTokenModule } from "src/protocol-v2/modules/CCIPTokenModule.sol";
import { VaultLiquidityModule } from "src/protocol-v2/modules/VaultLiquidityModule.sol";
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
//
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// Libraries
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { LedgityDataProvider } from "src/protocol-v2/libraries/LedgityDataProvider.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";
import { IFixedTermInvestmentVault } from "src/protocol-v2/interfaces/IFixedTermInvestmentVault.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";

/**
 * @title FixedTermInvestmentVault
 * @notice ERC-4626 vault for fixed-term investment operations with capped deposits and controlled exits.
 * @dev The vault is designed for one-shot operations where deposits are accepted up to
 *      `maxDepositCapacity`, direct withdrawals are locked until `operationEndDate`, and
 *      early exits can be coordinated through withdrawal requests. Setting
 *      `maxDepositCapacity` to zero disables the deposit cap. Setting `operationEndDate` to
 *      zero disables the direct withdrawal lock. Withdrawal requests are independently
 *      controlled by the owner through `updateWithdrawalRequestsEnabled`; disabling requests
 *      cancels pending requests and remints the burned shares so users keep exposure at the
 *      latest price per share.
 *
 * @author vBlackwhale (https://github.com/vblackwhale)
 */
contract FixedTermInvestmentVault is
  IFixedTermInvestmentVault,
  AdministeredUpgradable,
  CCIPTokenModule,
  VaultLiquidityModule
{
  // ======== LIBS ======== //
  using SafeERC20 for IERC20;
  using LedgityDataProvider for ILedgityDataProvider.WithdrawalRequest[];

  // ======== ERRORS ======== //

  error ZeroAmount();
  error ZeroAddress();
  error NoLTokenSet();
  error OnlyLiquidityManager();
  error MissingWithdrawalRequestFee();
  error RequestAlreadyProcessed();
  error InsufficientLiquidity();
  error InsufficientStakeForInstantWithdrawal();
  error TransferFailed();
  error DepositCapacityExceeded();
  error OperationNotEnded();
  error WithdrawalRequestsDisabled();
  error WithdrawalRequestSharesUnavailable();

  // ======== STORAGE ======== //

  // The legacy L-Token that can be migrated to vault shares
  IERC20 public lToken;

  // Address authorized to manage vault liquidity and process withdrawals
  address public liquidityManager;
  // Address that receives management and performance fees
  address payable public feeRecipient;

  // Target percentage of total assets to maintain in liquidity buffer in RAY
  uint256 public liquidityBufferRate;

  // Whether the vault uses Aave as a buffer strategy for idle funds
  bool public hasBufferStrategy;
  // Aave lending pool contract for buffer strategy operations
  IAaveLendingPoolV3 public aaveLendingPool;
  // Aave interest bearing token address (aToken) or zero address if no Aave integration
  IERC20 public aToken;

  // Token representing user's stake in the protocol for fee reductions
  IERC20 public stakeToken;
  // The amount of stake token required to receive a withdrawal fee reduction
  uint256 public stakeForFeeReduction;
  // The amount of stake token required to make instant withdrawal
  uint256 public stakeForInstantWithdrawal;

  // Array storing all withdrawal requests in chronological order
  ILedgityDataProvider.WithdrawalRequest[] public withdrawalRequests;
  // Maximum total assets that can be deposited. A zero value disables the cap.
  uint256 public maxDepositCapacity;
  // Timestamp when direct withdrawals and redemptions unlock. A zero value disables the lock.
  uint256 public operationEndDate;
  // Net shares burned for each withdrawal request, used to restore exposure if cancelled.
  mapping(uint256 => uint256) public withdrawalRequestShares;
  // Inverted flag keeps withdrawal requests enabled by default for upgrade compatibility.
  bool private _withdrawalRequestsDisabled;

  // The vault type identifier
  uint8 public vaultType;

  // ======== EVENTS ======== //

  /**
   * Emitted when a user requests a withdrawal
   * @param requestId Unique identifier for the withdrawal request
   * @param user Address of the user requesting withdrawal
   * @param shares Gross amount of shares submitted by the user
   * @param assets Net amount of assets reserved for the request
   * @param feeShares Amount of shares paid as withdrawal fee
   */
  event WithdrawalRequested(
    uint256 indexed requestId,
    address indexed user,
    uint256 shares,
    uint256 assets,
    uint256 feeShares
  );

  event WithdrawalRequestCancelled(
    uint256 indexed requestId,
    address indexed user,
    uint256 assets,
    uint256 shares
  );

  event MaxDepositCapacityUpdated(
    uint256 oldMaxDepositCapacity,
    uint256 newMaxDepositCapacity
  );

  event OperationEndDateUpdated(
    uint256 oldOperationEndDate,
    uint256 newOperationEndDate
  );

  event WithdrawalRequestsEnabledUpdated(
    bool oldEnabled,
    bool newEnabled
  );

  /**
   * Emitted when a withdrawal request is processed and fulfilled
   * @param requestId Unique identifier for the processed request
   * @param user Address of the user receiving the withdrawal
   * @param amount Amount of assets transferred to user
   */
  event WithdrawalProcessed(
    uint256 indexed requestId,
    address indexed user,
    uint256 amount
  );

  /**
   * Emitted when the liquidity manager and fee recipient are updated
   * @param liquidityManager The new liquidity manager address
   * @param feeRecipient The new fee recipient address
   */
  event VaultManagersUpdated(
    address indexed liquidityManager,
    address indexed feeRecipient
  );

  /**
   * Emitted when the liquidity buffer rate is updated
   * @param bufferRate The new liquidity buffer rate
   */
  event BufferRateUpdated(uint256 bufferRate);

  /**
   * Emitted when the vault parameters are updated
   * @param newLToken The new L-Token address
   * @param newStakeToken The new stake token address
   * @param newStakeForFeeReduction The new stake balance for fee reduction
   * @param newStakeForInstantWithdrawal The new stake balance for instant withdrawal
   * @param newAaveLendingPool The new Aave lending pool address
   */
  event VaultParamsUpdated(
    IERC20 indexed newLToken,
    IERC20 indexed newStakeToken,
    uint256 newStakeForFeeReduction,
    uint256 newStakeForInstantWithdrawal,
    IAaveLendingPoolV3 indexed newAaveLendingPool
  );

  // ======== INITIALIZE ======== //

  /**
   * @notice Initializes the Vault contract
   * @param params Struct containing vault-specific initialization parameters
   * @param vaultLiquidityInitParams Struct containing initialization parameters for fees, APR, and other settings
   */
  function initialize(
    VaultParams calldata params,
    VaultLiquidityInitParams calldata vaultLiquidityInitParams
  ) public initializer {
    if (
      address(params.asset) == address(0) ||
      params.liquidityManager == address(0) ||
      params.feeRecipient == address(0)
    ) revert ZeroAddress();

    __ERC20_init(params.name, params.symbol);
    __ERC4626_init(IERC20Upgradeable(address(params.asset)));
    __AdministeredUpgradable_init(
      params.globalOwner,
      params.globalPause,
      params.globalAccessList
    );
    // Initialize the liquidity module with APR and fee rates
    __VaultLiquidityModule_init(
      vaultLiquidityInitParams,
      address(params.asset)
    );
    /// @dev This simplifies the cross chain initialization process before being set back to the global owner
    __CCIPCompatible_init(msg.sender);

    liquidityManager = params.liquidityManager;
    feeRecipient = params.feeRecipient;

    lToken = params.lToken;
    stakeToken = params.stakeToken;
    stakeForFeeReduction = params.stakeForFeeReduction;
    stakeForInstantWithdrawal = params.stakeForInstantWithdrawal;
    liquidityBufferRate = params.liquidityBufferRate;

    _setupBufferStrategy(params.aaveLendingPool);

    vaultType = 2;
  }

  // ======== MODIFIERS ======== //

  /* @notice Restricts function access to the authorized liquidity manager
   */
  modifier onlyLiquidityManager() {
    if (msg.sender != liquidityManager) revert OnlyLiquidityManager();
    _;
  }

  // ======== OVERRIDES ======== //

  /**
   * @notice Restricts token transfers from or to restricted addresses
   * @param from The sender of the transfer
   * @param to The recipient of the transfer
   * @param amount The amount of tokens being transferred
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20Upgradeable) whenNotPaused {
    if (
      msg.sender != owner() &&
      (globalRestrict.isRestricted(from) ||
        globalRestrict.isRestricted(to))
    ) {
      revert UserIsRestricted();
    }

    super._beforeTokenTransfer(from, to, amount);
  }

  /**
   * @notice Returns the owner of the contract
   * @return The owner's address
   */
  function owner()
    public
    view
    override(OwnableUpgradeable, AdministeredUpgradable)
    returns (address)
  {
    return globalOwner.owner();
  }

  /* @notice Returns the number of decimals used for the vault token (18)
   * @return The number of decimals
   */
  function decimals()
    public
    pure
    override(ERC20Upgradeable, ERC4626Upgradeable)
    returns (uint8)
  {
    return 18;
  }

  /**
   * @notice Handles minting through CCIP cross-chain transfers by taking into account asset rebalance
   * @param account The account to mint shares to
   * @param shares The amount of shares to mint
   */
  function _handleMint(
    address account,
    uint256 shares
  ) internal override(CCIPTokenModule) returns (bool) {
    harvestFees();
    _addAssets(convertToAssets(shares));

    _mint(account, shares);
    return true;
  }

  /**
   * @notice Handles burning through CCIP cross-chain transfers by taking into account asset rebalance
   * @param account The account to burn shares from
   * @param shares The amount of shares to burn
   */
  function _handleBurn(
    address account,
    uint256 shares
  ) internal override(CCIPTokenModule) returns (bool) {
    harvestFees();
    _withdrawAssets(convertToAssets(shares));

    _burn(account, shares);
    return true;
  }

  // ======== VIEW ======== //

  /**
   * @notice Get the buffer strategy assets
   * @return The buffer strategy assets
   */
  function getBufferAssets() public view returns (uint256) {
    return
      hasBufferStrategy
        ? aToken.balanceOf(address(this))
        : IERC20(asset()).balanceOf(address(this));
  }

  /**
   * @notice Get withdrawal requests with optional filtering
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return requests Array of withdrawal requests with read structure
   */
  function getWithdrawalRequests(
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    )
  {
    return
      withdrawalRequests.getWithdrawalRequests(
        stakeToken,
        stakeForFeeReduction,
        onlyPending,
        maxRange
      );
  }

  /**
   * @notice Get withdrawal requests for a specific user
   * @param user The user address
   * @param onlyPending If true, only return non-processed requests
   * @param maxRange Maximum number of requests to return (0 = return all)
   * @return requests Array of withdrawal requests for the user with read structure
   */
  function getUserWithdrawalRequests(
    address user,
    bool onlyPending,
    uint256 maxRange
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    )
  {
    return
      withdrawalRequests.getUserWithdrawalRequests(
        stakeToken,
        stakeForFeeReduction,
        user,
        onlyPending,
        maxRange
      );
  }

  /**
   * @notice Get specific withdrawal requests by their IDs
   * @param requestIds Array of request IDs to fetch
   * @return requests Array of withdrawal requests corresponding to the IDs with read structure
   */
  function getWithdrawalRequestsByIds(
    uint256[] calldata requestIds
  )
    external
    view
    returns (
      ILedgityDataProvider.WithdrawalRequestRead[] memory requests
    )
  {
    return
      withdrawalRequests.getWithdrawalRequestsByIds(
        stakeToken,
        stakeForFeeReduction,
        requestIds
      );
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

  /**
   * @notice Return whether users can create withdrawal requests.
   * @return enabled True when new withdrawal requests are accepted.
   */
  function withdrawalRequestsEnabled()
    public
    view
    returns (bool enabled)
  {
    return !_withdrawalRequestsDisabled;
  }

  // ======== INTERNAL HELPERS ======== //

  /**
   * @notice Setup the buffer strategy
   * @param aaveLendingPool_ The Aave lending pool address
   */
  function _setupBufferStrategy(
    IAaveLendingPoolV3 aaveLendingPool_
  ) private {
    if (address(aaveLendingPool_) != address(0)) {
      aaveLendingPool = aaveLendingPool_;
      aToken = IERC20(
        aaveLendingPool_
          .getReserveData(address(asset()))
          .aTokenAddress
      );

      // Validate that aToken was properly retrieved
      if (address(aToken) != address(0)) {
        hasBufferStrategy = true;
        IERC20(asset()).forceApprove(
          address(aaveLendingPool_),
          type(uint256).max
        );
      }
    } else {
      hasBufferStrategy = false;
      aaveLendingPool = IAaveLendingPoolV3(address(0));
      aToken = IERC20(address(0));
    }
  }

  // ======== BUFFER INTERNAL HELPERS ======== //

  /**
   * @notice Deposits the specified amount of assets into the Aave Lending Pool
   * @param amountAssets The amount of assets to deposit
   */
  function _investBuffer(uint256 amountAssets) private {
    /// @dev We already approved the contract in the initializer
    aaveLendingPool.deposit(asset(), amountAssets, address(this), 0);
  }

  /**
   * @notice Withdraws the specified amount of assets from the Aave Lending Pool
   * @param to The address to which the assets will be transferred
   * @param amountAssets The amount of assets to withdraw
   */
  function _withdrawBuffer(address to, uint256 amountAssets) private {
    if (hasBufferStrategy) {
      /// @dev In AAVE the aTokens are rebase tokens so underlying amount is the same as aToken amount
      aaveLendingPool.withdraw(asset(), amountAssets, to);
    } else {
      IERC20(asset()).safeTransfer(to, amountAssets);
    }
  }

  // ======== VAULT INTERNAL HELPERS ======== //

  /**
   * @notice Internal function to handle shares conversion and fees on withdrawal
   * @param owner_ The address that called the withdraw function
   * @param shares_ The number of shares to withdraw
   */
  function _burnSharesTakeFeesOnWithdrawal(
    address owner_,
    uint256 shares_
  ) internal returns (uint256 netAssets, uint256 withdrawalFee) {
    if (shares_ == 0) revert ZeroAmount();

    // Take fees before processing
    harvestFees();

    // Calculate underlying amount using updated rate
    if (
      stakeForFeeReduction != 0 &&
      address(stakeToken) != address(0) &&
      stakeToken.balanceOf(owner_) < stakeForFeeReduction
    ) {
      withdrawalFee = _computeWithdrawalFee(shares_, owner_);
      /// @dev Transfer fee shares to recipient to avoid dilution
      _transfer(owner_, feeRecipient, withdrawalFee);
    }

    uint256 netShares = shares_ - withdrawalFee;
    netAssets = convertToAssets(netShares);

    _burn(owner_, netShares);
    _withdrawAssets(netAssets);
  }

  /**
   * @notice Internal function to handle withdraw tokens
   * @param caller_ The address that called the withdraw function
   * @param receiver_ The address to receive the underlying
   * @param owner_ The owner of the shares tokens
   * @param shares_ The amount of shares tokens to withdraw
   */
  function _withdrawFromVault(
    address caller_,
    address receiver_,
    address owner_,
    uint256 /* assets_ */,
    uint256 shares_
  )
    internal
    whenNotPaused
    notRestricted(caller_)
    returns (uint256 netAssets)
  {
    /// @dev owner and receiver (from/to) restricted status is checked in _beforeTokenTransfer

    if (operationEndDate != 0 && block.timestamp < operationEndDate) {
      revert OperationNotEnded();
    }

    if (
      stakeForInstantWithdrawal != 0 &&
      address(stakeToken) != address(0) &&
      stakeToken.balanceOf(caller_) < stakeForInstantWithdrawal
    ) revert InsufficientStakeForInstantWithdrawal();

    if (caller_ != owner_) {
      _spendAllowance(owner_, caller_, shares_);
    }

    (netAssets, ) = _burnSharesTakeFeesOnWithdrawal(owner_, shares_);

    // slither-disable-next-line reentrancy-no-eth
    _withdrawBuffer(receiver_, netAssets);

    emit Withdraw(caller_, receiver_, owner_, netAssets, shares_);
  }

  /**
   * @notice Internal function to handle depositing underlying
   * @param caller_ The address that called the deposit function
   * @param receiver_ The address to receive the minted shares
   * @param assets_ The amount of underlying to deposit
   */
  function _depositToVault(
    address caller_,
    address receiver_,
    uint256 assets_,
    uint256 /* shares */
  )
    internal
    whenNotPaused
    notRestricted(caller_)
    returns (uint256 netShares)
  {
    /// @dev owner and receiver (from/to) restricted status is checked in _beforeTokenTransfer

    if (assets_ == 0) revert ZeroAmount();
    if (
      maxDepositCapacity != 0 &&
      maxDepositCapacity < totalAssets() + assets_
    ) revert DepositCapacityExceeded();

    // Take fees before processing
    harvestFees();

    // Apply capital deployment impact to amount of shares
    uint256 maturityImpact = _computeMaturityImpact(assets_);
    uint256 netDeposit = assets_ - maturityImpact;
    netShares = convertToShares(netDeposit);

    /// @dev Add assets before computing the expected buffer balance
    _addAssets(netDeposit);

    // Calculate expected buffer balance after this deposit
    uint256 expectedBufferBalance = (totalAssets() *
      liquidityBufferRate) / RAY;

    uint256 currentBufferBalance = getBufferAssets();

    uint256 bufferAmount;
    uint256 vaultAmount;

    if (currentBufferBalance < expectedBufferBalance) {
      uint256 bufferDeficit = expectedBufferBalance -
        currentBufferBalance;

      // Use smaller amount between deposit amount and buffer deficit
      bufferAmount = assets_ < bufferDeficit
        ? assets_
        : bufferDeficit;
      vaultAmount = assets_ - bufferAmount;
    } else {
      // Buffer is at or above target - send all to liquidity manager
      bufferAmount = 0;
      vaultAmount = assets_;
    }

    IERC20(asset()).safeTransferFrom(caller_, address(this), assets_);

    // slither-disable-next-line reentrancy-no-eth
    if (0 < bufferAmount && hasBufferStrategy) {
      _investBuffer(bufferAmount);
      /// @dev If no buffer strategy, assets stay in contract as underlying
    }
    if (0 < vaultAmount) {
      IERC20(asset()).safeTransfer(liquidityManager, vaultAmount);
    }

    _mint(receiver_, netShares);

    emit Deposit(caller_, receiver_, assets_, netShares);
  }

  // ======== WRITE FUNCTIONS ======== //

  /**
   * @notice Migrate legacy L-Tokens to vault shares at 1:1 rate
   * @param amount Amount of L-Tokens to migrate
   * @return shares Amount of vault shares minted
   * @dev No maturity impact applied since capital remains deployed
   */
  function migrateLToken(
    uint256 amount
  )
    public
    whenNotPaused
    notRestricted(msg.sender)
    returns (uint256 shares)
  {
    if (address(lToken) == address(0)) revert NoLTokenSet();
    if (amount == 0) revert ZeroAmount();

    // Take fees before processing
    harvestFees();

    lToken.safeTransferFrom(msg.sender, liquidityManager, amount);

    // Calculate shares amount using updated rate (treat L-Tokens same as underlying)
    /// @dev No maturity impact on migration since the capital stays deployed
    shares = convertToShares(amount);

    _addAssets(amount);
    _mint(msg.sender, shares);

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
    override(ERC4626Upgradeable, ILedgityYieldVault)
    returns (uint256)
  {
    return _depositToVault(msg.sender, receiver, assets, 0);
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
    override(ERC4626Upgradeable, ILedgityYieldVault)
    returns (uint256)
  {
    return
      _depositToVault(
        msg.sender,
        receiver,
        convertToAssets(shares),
        0
      );
  }

  /**
   * @notice Withdraw assets (underlying) by burning shares (shares tokens)
   * @param assets_ The amount of underlying to withdraw
   * @param receiver_ The address to receive the withdrawn underlying
   * @param owner_ The address of the owner of the shares
   * @return sharesPreview The number of shares burned
   */
  function withdraw(
    uint256 assets_,
    address receiver_,
    address owner_
  )
    public
    override(ERC4626Upgradeable, ILedgityYieldVault)
    returns (uint256)
  {
    return
      _withdrawFromVault(
        msg.sender,
        receiver_,
        owner_,
        0,
        convertToShares(assets_)
      );
  }

  /**
   * @notice Redeem shares (shares tokens) for assets (underlying)
   * @param shares_ The number of shares to redeem
   * @param receiver_ The address to receive the underlying
   * @param owner_ The address of the owner of the shares
   * @return assetsPreview The amount of underlying received
   */
  function redeem(
    uint256 shares_,
    address receiver_,
    address owner_
  )
    public
    override(ERC4626Upgradeable, ILedgityYieldVault)
    returns (uint256)
  {
    return
      _withdrawFromVault(msg.sender, receiver_, owner_, 0, shares_);
  }

  /**
   * @notice Request a withdrawal that will be processed asynchronously
   * @param shares Amount of vault shares to withdraw
   * @dev Requires gas fee payment and burns shares immediately. Requests remain available
   *      after the operation end date if the owner leaves them enabled.
   * @dev Sending the full ETH balance is intended behaviour.
   */
  function requestWithdrawal(
    uint256 shares
  ) public payable whenNotPaused notRestricted(msg.sender) {
    if (_withdrawalRequestsDisabled)
      revert WithdrawalRequestsDisabled();
    if (msg.value < withdrawalGasFee)
      revert MissingWithdrawalRequestFee();

    // Transfer gas fee to fee recipient
    /// @dev Use call since the fee recipient is a multisig that requires more that enforced 2300 .transfer() gas
    (bool success, ) = feeRecipient.call{
      value: address(this).balance
    }("");
    if (!success) revert TransferFailed();

    (
      uint256 netAssets,
      uint256 appliedWithdrawalFee
    ) = _burnSharesTakeFeesOnWithdrawal(msg.sender, shares);

    // Create withdrawal request
    withdrawalRequests.push(
      ILedgityDataProvider.WithdrawalRequest({
        user: msg.sender,
        amount: netAssets,
        timestamp: block.timestamp,
        processed: false
      })
    );

    emit WithdrawalRequested(
      withdrawalRequests.length - 1,
      msg.sender,
      shares,
      netAssets,
      appliedWithdrawalFee
    );

    withdrawalRequestShares[withdrawalRequests.length - 1] =
      shares -
      appliedWithdrawalFee;
  }

  /**
   * @notice Harvest buffer rewards and collect management/performance fees
   * @dev Can be called by anyone to update vault state and collect fees
   */
  function harvestFees() public {
    // Take management and performance fees
    _takeFees(feeRecipient);
  }

  // ======== ADMIN ======== //

  /**
   * @notice Update the maximum deposit capacity.
   * @param maxDepositCapacity_ New capacity in underlying asset units. Set to zero to disable the cap.
   * @dev Only the vault owner can update the capacity. Lowering it below current assets
   *      blocks additional deposits without forcing existing users out.
   */
  function updateMaxDepositCapacity(
    uint256 maxDepositCapacity_
  ) external onlyOwner {
    uint256 oldMaxDepositCapacity = maxDepositCapacity;
    maxDepositCapacity = maxDepositCapacity_;

    emit MaxDepositCapacityUpdated(
      oldMaxDepositCapacity,
      maxDepositCapacity_
    );
  }

  /**
   * @notice Update the timestamp when direct withdrawals and redemptions unlock.
   * @param operationEndDate_ New unlock timestamp. Set to zero to disable the lock.
   * @dev The end date controls only direct ERC-4626 withdrawals and redemptions. Withdrawal
   *      requests are controlled independently by `updateWithdrawalRequestsEnabled`.
   */
  function updateOperationEndDate(
    uint256 operationEndDate_
  ) external onlyOwner {
    uint256 oldOperationEndDate = operationEndDate;
    operationEndDate = operationEndDate_;

    emit OperationEndDateUpdated(
      oldOperationEndDate,
      operationEndDate_
    );
  }

  /**
   * @notice Enable or disable new withdrawal requests.
   * @param enabled True to accept new requests, false to block them.
   * @dev Disabling also cancels all pending requests. If the request array is too large to
   *      process in one transaction, use `cancelPendingWithdrawalRequests` with selected ids.
   * @dev Loop DoS is an operator concern: `cancelPendingWithdrawalRequests` is the escape hatch.
   */
  function updateWithdrawalRequestsEnabled(
    bool enabled
  ) external onlyOwner {
    bool oldEnabled = withdrawalRequestsEnabled();
    _withdrawalRequestsDisabled = !enabled;

    emit WithdrawalRequestsEnabledUpdated(oldEnabled, enabled);

    if (!enabled) {
      for (uint256 i; i < withdrawalRequests.length; i++) {
        if (!withdrawalRequests[i].processed) {
          _cancelWithdrawalRequest(i);
        }
      }
    }
  }

  /**
   * @notice Cancel selected pending withdrawal requests.
   * @param requestIds Withdrawal request ids to cancel.
   * @dev Each cancellation marks the request as processed so it cannot later be paid by the
   *      liquidity manager, restores vault accounting at the latest PPS, and remints the
   *      burned net shares to the request owner.
   */
  function cancelPendingWithdrawalRequests(
    uint256[] calldata requestIds
  ) external onlyOwner {
    for (uint256 i; i < requestIds.length; i++) {
      _cancelWithdrawalRequest(requestIds[i]);
    }
  }

  /**
   * @notice Burns shares from a blacklisted user and mints them to another address
   * @param burnFrom The address to burn shares from
   * @param remintTo The address to mint shares to
   */
  function burnAndRemintBlacklistedShares(
    address burnFrom,
    address remintTo
  ) public onlyOwner {
    uint256 shares_ = balanceOf(burnFrom);
    _burn(burnFrom, shares_);
    _mint(remintTo, shares_);
  }

  /**
   * @notice Deposit assets into the liquidity buffer
   * @param assets Amount of assets to deposit
   * @dev Only callable by liquidity manager
   */
  function depositToBuffer(
    uint256 assets
  ) public onlyLiquidityManager {
    // Transfer assets from fund wallet to contract
    // slither-disable-next-line arbitrary-send-erc20
    IERC20(asset()).safeTransferFrom(
      liquidityManager,
      address(this),
      assets
    );
    if (hasBufferStrategy) _investBuffer(assets);
  }

  /**
   * @notice Remove excess assets from the liquidity buffer
   * @param amount Amount of assets to withdraw from buffer
   * @dev Only callable by liquidity manager
   */
  function skimBuffer(uint256 amount) public onlyLiquidityManager {
    _withdrawBuffer(liquidityManager, amount);
  }

  /**
   * @notice Process queued withdrawal requests by providing liquidity
   * @param requestIds Array of request IDs to process
   * @param addAssets Additional liquidity provided by liquidity manager
   * @dev Only callable by liquidity manager, uses buffer + added liquidity
   * @dev Audit/LLM note: fulfillment is an admin/liquidity-manager operation after
   *      operational review, not a permissionless withdrawal path. Restricted-account
   *      handling is enforced at user-facing entry/request paths and before admin
   *      processing; sending assets to a later-restricted receiver would be an
   *      operational/compliance error, not theft of vault assets or broken share accounting.
   */
  function processRequests(
    uint256[] calldata requestIds,
    uint256 addAssets
  ) public onlyLiquidityManager {
    if (0 < addAssets) {
      // slither-disable-next-line arbitrary-send-erc20
      IERC20(asset()).safeTransferFrom(
        liquidityManager,
        address(this),
        addAssets
      );
    }

    // Take fees before processing
    harvestFees();

    // Calculate total assets needed for selected requests.
    // Mark each request processed here to catch duplicate IDs in the array.
    uint256 assetsTotal;
    for (uint256 i; i < requestIds.length; i++) {
      ILedgityDataProvider.WithdrawalRequest
        storage request = withdrawalRequests[requestIds[i]];

      if (request.processed) revert RequestAlreadyProcessed();
      request.processed = true;

      assetsTotal += request.amount;
    }

    // Check available liquidity (buffer + added liquidity)
    uint256 bufferBalance = getBufferAssets();
    if ((bufferBalance + addAssets) < assetsTotal)
      revert InsufficientLiquidity();

    // Withdraw required assets from buffer if needed
    if (hasBufferStrategy && addAssets < assetsTotal) {
      // slither-disable-next-line reentrancy-no-eth
      _withdrawBuffer(address(this), assetsTotal - addAssets);
    }

    // Process each request
    for (uint256 i; i < requestIds.length; i++) {
      uint256 requestId = requestIds[i];
      ILedgityDataProvider.WithdrawalRequest
        storage request = withdrawalRequests[requestId];

      // Transfer assets to user
      IERC20(asset()).safeTransfer(request.user, request.amount);

      emit WithdrawalProcessed(
        requestId,
        request.user,
        request.amount
      );
    }
  }

  /**
   * @notice Updates the liquidity manager and fee recipient
   * @param newLiquidityManager The new liquidity manager address
   * @param newFeeRecipient The new fee recipient address
   * @dev Only callable by global owner
   */
  function updateVaultManagers(
    address newLiquidityManager,
    address payable newFeeRecipient
  ) public onlyOwner {
    if (
      newLiquidityManager == address(0) ||
      newFeeRecipient == address(0)
    ) revert ZeroAddress();

    liquidityManager = newLiquidityManager;
    feeRecipient = newFeeRecipient;

    emit VaultManagersUpdated(newLiquidityManager, newFeeRecipient);
  }

  /**
   * @notice Updates the liquidity buffer rate
   * @param bufferRate The new liquidity buffer rate
   * @dev Only callable by global owner
   */
  function updateBufferRate(uint256 bufferRate) public onlyOwner {
    liquidityBufferRate = bufferRate;

    emit BufferRateUpdated(bufferRate);
  }

  /**
   * @notice Updates vault parameters
   * @param newLToken The new L-Token address
   * @param newStakeToken The new stake token address
   * @param newStakeForFeeReduction The new stake balance for fee reduction
   * @param newStakeForInstantWithdrawal The new stake balance for instant withdrawal
   * @param newAaveLendingPool The new Aave lending pool address
   * @dev Only callable by global owner
   */
  function updateVaultParams(
    IERC20 newLToken,
    IERC20 newStakeToken,
    uint256 newStakeForFeeReduction,
    uint256 newStakeForInstantWithdrawal,
    IAaveLendingPoolV3 newAaveLendingPool
  ) public onlyOwner {
    lToken = newLToken;
    stakeToken = newStakeToken;

    stakeForFeeReduction = newStakeForFeeReduction;
    stakeForInstantWithdrawal = newStakeForInstantWithdrawal;

    _setupBufferStrategy(newAaveLendingPool);

    emit VaultParamsUpdated(
      newLToken,
      newStakeToken,
      newStakeForFeeReduction,
      newStakeForInstantWithdrawal,
      newAaveLendingPool
    );
  }

  /**
   * @notice Cancel a pending request and restore the user's vault exposure.
   * @param requestId Withdrawal request id to cancel.
   * @dev The request is marked processed before minting shares back. The vault restores the
   *      current asset value of the burned shares, so cancellation preserves the user's
   *      exposure at the latest price per share while preventing later request processing.
   */
  function _cancelWithdrawalRequest(uint256 requestId) private {
    ILedgityDataProvider.WithdrawalRequest
      storage request = withdrawalRequests[requestId];

    if (request.processed) revert RequestAlreadyProcessed();

    uint256 shares = withdrawalRequestShares[requestId];
    if (shares == 0) revert WithdrawalRequestSharesUnavailable();

    request.processed = true;

    uint256 assets = convertToAssets(shares);
    _addAssets(assets);
    _mint(request.user, shares);
    emit WithdrawalRequestCancelled(
      requestId,
      request.user,
      assets,
      shares
    );
  }
}
