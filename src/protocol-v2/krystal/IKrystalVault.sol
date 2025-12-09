// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

library AssetLib {
  enum AssetType {
    ERC20,
    ERC721,
    ERC1155
  }

  struct Asset {
    AssetType assetType;
    address strategy;
    address token;
    uint256 tokenId;
    uint256 amount;
  }
}

/**
 * @title IKrystalVault
 * @notice Interface for the Krystal vault contract
 */
interface IKrystalVault {
  event VaultDeposit(
    address indexed vaultFactory,
    address indexed account,
    uint256 principalAmount,
    uint256 shares
  );

  event VaultWithdraw(
    address indexed vaultFactory,
    address indexed account,
    uint256 principalAmount,
    uint256 shares
  );

  event VaultHarvestPrivate(
    address indexed vaultFactory,
    address indexed owner,
    uint256 principalHarvestedAmount
  );

  event VaultOwnerChanged(
    address indexed vaultFactory,
    address indexed oldOwner,
    address indexed newOwner
  );

  event SetVaultAdmin(
    address indexed vaultFactory,
    address indexed _address,
    bool indexed _isAdmin
  );

  error VaultPaused();
  error InvalidAssetToken();
  error InvalidAssetAmount();
  error InvalidSweepAsset();
  error InvalidAssetStrategy();
  error DepositAllowed();
  error DepositNotAllowed();
  error MaxPositionsReached();
  error InvalidShares();
  error Unauthorized();
  error InsufficientShares();
  error FailedToSendEther();
  error InvalidWETH();
  error InsufficientReturnAmount();
  error ExceedMaxAllocatePerBlock();
  error StrategyDelegateCallFailed();

  function balanceOf(address account) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function SHARES_PRECISION() external view returns (uint256);

  function vaultOwner() external view returns (address);

  function WETH() external view returns (address);

  function deposit(
    uint256 principalAmount,
    uint256 minShares
  ) external payable returns (uint256 returnShares);

  function depositPrincipal(
    uint256 principalAmount
  ) external payable returns (uint256 shares);

  function withdraw(
    uint256 shares,
    bool unwrap,
    uint256 minReturnAmount
  ) external returns (uint256 returnAmount);

  function withdrawPrincipal(
    uint256 amount,
    bool unwrap
  ) external returns (uint256 returnAmount);

  function harvest(
    AssetLib.Asset calldata asset,
    uint64 gasFeeBasisPoint,
    uint256 amountTokenOutMin
  ) external returns (AssetLib.Asset[] memory harvestedAssets);

  function harvestPrivate(
    AssetLib.Asset[] calldata asset,
    bool unwrap,
    uint64 gasFeeBasisPoint,
    uint256 amountTokenOutMin
  ) external;

  function getTotalValue() external view returns (uint256);

  function grantAdminRole(address _address) external;

  function revokeAdminRole(address _address) external;

  function sweepToken(address[] calldata tokens) external;

  function sweepERC721(
    address[] calldata _tokens,
    uint256[] calldata _tokenIds
  ) external;

  function sweepERC1155(
    address[] calldata _tokens,
    uint256[] calldata _tokenIds
  ) external;

  function transferOwnership(address _newOwner) external;

  function getInventory()
    external
    view
    returns (AssetLib.Asset[] memory assets);

  function getVaultConfig()
    external
    view
    returns (
      bool allowDeposit,
      uint8 rangeStrategyType,
      uint8 tvlStrategyType,
      address principalToken,
      address[] memory supportedAddresses,
      uint16 vaultOwnerFeeBasisPoint
    );
}
