// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC721, IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IERC4906 } from "@openzeppelin/contracts/interfaces/IERC4906.sol";

interface IStakingPositions is IERC4906, IERC721Metadata {
  struct LockedBalance {
    int128 amount;
    uint256 end;
  }

  struct UserPoint {
    int128 bias;
    int128 slope; // # -dweight / dt
    uint256 timestamp;
  }

  struct GlobalPoint {
    int128 bias;
    int128 slope; // # -dweight / dt
    uint256 timestamp;
  }

  enum DepositType {
    DEPOSIT_FOR_TYPE,
    CREATE_LOCK_TYPE,
    INCREASE_LOCK_AMOUNT,
    INCREASE_UNLOCK_TIME
  }

  struct NFTData {
    uint256 tokenId;
    LockedBalance locked;
    uint256 votingPower;
    uint256 votingPowerAt;
    address owner;
  }

  error NonExistentToken();
  error ZeroAddress();
  error SameAddress();
  error NotApprovedOrOwner();
  error ERC721ReceiverRejectedTokens();
  error ERC721TransferToNonERC721ReceiverImplementer();
  error LockExpired();
  error NoLockFound();
  error LockDurationNotInFuture();
  error LockDurationTooLong();
  error LockNotExpired();
  error NotOwner();
  error ZeroAmount();

  event Deposit(
    address indexed from,
    uint256 indexed tokenId,
    DepositType indexed depositType,
    uint256 value,
    uint256 locktime,
    uint256 timestamp
  );
  event Withdraw(
    address indexed from,
    uint256 indexed tokenId,
    uint256 value,
    uint256 timestamp
  );

  event Supply(uint256 prevSupply, uint256 supply);

  event BreakerActivated();

  /// @notice Address of token (VELO) used to create a veNFT
  function token() external view returns (address);

  /// @notice Address of art proxy used for on-chain art generation
  function artProxy() external view returns (address);

  /// @dev Current count of token
  function tokenId() external view returns (uint256);

  /// @notice Maximum lock time in seconds
  function maxTime() external view returns (uint256);

  /// @notice Maximum lock time as int128
  function iMaxTime() external view returns (int128);

  /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function decimals() external view returns (uint8);

  /// @inheritdoc IERC721Metadata
  function tokenURI(
    uint256 tokenId
  ) external view returns (string memory);

  /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @dev Mapping from owner address to mapping of index to tokenId
  function ownerToNFTokenIdList(
    address _owner,
    uint256 _index
  ) external view returns (uint256 _tokenId);

  /// @inheritdoc IERC721
  function ownerOf(
    uint256 tokenId
  ) external view returns (address owner);

  /// @notice Get the balance of a user's veNFTs, replaces the ERC721 balanceOf function
  /// @param _owner .
  /// @return balance of _owner
  function balanceOfAccountNFT(
    address _owner
  ) external view returns (uint256 balance);

  /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC721
  function getApproved(
    uint256 _tokenId
  ) external view returns (address operator);

  /// @inheritdoc IERC721
  function isApprovedForAll(
    address owner,
    address operator
  ) external view returns (bool);

  /// @notice Check whether spender is owner or an approved user for a given veNFT
  /// @param _spender .
  /// @param _tokenId .
  function isApprovedOrOwner(
    address _spender,
    uint256 _tokenId
  ) external view returns (bool);

  /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC721
  function approve(address to, uint256 tokenId) external;

  /// @inheritdoc IERC721
  function setApprovalForAll(
    address operator,
    bool approved
  ) external;

  /// @inheritdoc IERC721
  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) external;

  /// @inheritdoc IERC721
  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) external;

  /// @inheritdoc IERC721
  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes calldata data
  ) external;

  /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceID
  ) external view returns (bool);

  /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @notice Total count of epochs witnessed since contract creation
  function epoch() external view returns (uint256);

  /// @notice Total amount of token() deposited
  function supply() external view returns (uint256);

  function userPointEpoch(
    uint256 _tokenId
  ) external view returns (uint256 _epoch);

  /// @notice time -> signed slope change
  function slopeChanges(
    uint256 _timestamp
  ) external view returns (int128);

  /// @notice Global point history at a given index
  function getPointHistory(
    uint256 _loc
  ) external view returns (GlobalPoint memory);

  /// @notice Get the LockedBalance (amount, end) of a _tokenId
  /// @param _tokenId .
  /// @return LockedBalance of _tokenId
  function getLockedBalance(
    uint256 _tokenId
  ) external view returns (LockedBalance memory);

  /// @notice User -> UserPoint[userEpoch]
  function getUserPointHistory(
    uint256 _tokenId,
    uint256 _loc
  ) external view returns (UserPoint memory);

  /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Record global data to checkpoint
  function checkpoint() external;

  /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
  /// @dev Anyone (even a smart contract) can deposit for someone else, but
  ///      cannot extend their locktime and deposit for a brand new user
  /// @param _tokenId lock NFT
  /// @param _value Amount to add to user's lock
  function depositFor(uint256 _tokenId, uint256 _value) external;

  /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lockDuration`
  /// @param _value Amount to deposit
  /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
  /// @return TokenId of created veNFT
  function createLock(
    uint256 _value,
    uint256 _lockDuration
  ) external returns (uint256);

  /// @notice Deposit `_value` additional tokens for `_tokenId` without modifying the unlock time
  /// @param _value Amount of tokens to deposit and add to the lock
  function increaseAmount(uint256 _tokenId, uint256 _value) external;

  /// @notice Extend the unlock time for `_tokenId`
  ///         Cannot extend lock time of permanent locks
  /// @param _lockDuration New number of seconds until tokens unlock
  function increaseUnlockTime(
    uint256 _tokenId,
    uint256 _lockDuration
  ) external;

  /// @notice Withdraw all tokens for `_tokenId`
  /// @dev Only possible if the lock is both expired and not permanent
  ///      This will burn the veNFT. Any rebases or rewards that are unclaimed
  ///      will no longer be claimable. Claim all rebases and rewards prior to calling this.
  function withdraw(uint256 _tokenId) external;

  /*///////////////////////////////////////////////////////////////
                           GAUGE VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @notice Total amount of voting power of a user across all veNFTs
  /// @dev Same as getUserTotalVotingPower
  function balanceOf(
    address owner
  ) external view returns (uint256 balance);

  /// @notice Get the voting power for _tokenId at the current timestamp
  /// @dev Returns 0 if called in the same block as a transfer.
  /// @param _tokenId .
  /// @return Voting power
  function balanceOfNFT(
    uint256 _tokenId
  ) external view returns (uint256);

  /// @notice Get the voting power for _tokenId at a given timestamp
  /// @param _tokenId .
  /// @param _t Timestamp to query voting power
  /// @return Voting power
  function balanceOfNFTAt(
    uint256 _tokenId,
    uint256 _t
  ) external view returns (uint256);

  /// @notice Calculate total voting power at current timestamp
  /// @return Total voting power at current timestamp
  function totalSupply() external view returns (uint256);

  /// @notice Calculate total voting power at a given timestamp
  /// @param _t Timestamp to query total voting power
  /// @return Total voting power at given timestamp
  function totalSupplyAt(uint256 _t) external view returns (uint256);

  /// @notice Get all NFT data for a user
  /// @param _user Address to query NFTs for
  /// @return Array of NFTData structs containing all user's NFT information
  function getUserNFTs(
    address _user
  ) external view returns (NFTData[] memory);

  /// @notice Get total voting power for a user across all their NFTs at current timestamp
  /// @param _user Address to query total voting power for
  /// @return Total voting power across all user's NFTs
  /// @dev Same as balanceOf
  function getUserTotalVotingPower(
    address _user
  ) external view returns (uint256);

  /// @notice Get total voting power for a user across all their NFTs at a specific timestamp
  /// @param _user Address to query total voting power for
  /// @param _t Timestamp to query voting power at
  /// @return Total voting power across all user's NFTs at given timestamp
  function getUserTotalVotingPowerAt(
    address _user,
    uint256 _t
  ) external view returns (uint256);

  /*///////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Set art proxy (owner only)
  function setArtProxy(address _proxy) external;

  /// @notice Set maximum lock time (owner only)
  function setMaxTime(uint256 _maxTime) external;

  /// @notice Unlock all veNFTs (owner only)
  function unlockAll() external;
}
