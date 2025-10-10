// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC721, IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IVotingEscrow is IERC721Metadata {
  struct UserPoint {
    int128 bias;
    int128 slope; // # -dweight / dt
    uint256 ts;
  }

  struct LockedBalance {
    int128 amount;
    uint256 end;
  }

  error LockNotExpired();
  error NoLockFound();
  error NonExistentToken();
  error NotApprovedOrOwner();
  error NotOwner();
  error AlreadyVoted();
  error AmountTooBig();
  error ZeroBalance();

  event deposit(
    address indexed provider,
    uint256 indexed tokenId,
    uint256 value,
    uint256 locktime,
    uint256 ts
  );
  event Withdraw(
    address indexed provider,
    uint256 indexed tokenId,
    uint256 value,
    uint256 ts
  );
  event Supply(uint256 prevSupply, uint256 supply);

  /// @notice Get the current balance of a veNFT
  function balanceOfNFT(
    uint256 _tokenId
  ) external view returns (uint256);

  /// @notice Get the balance of a veNFT at a specific timestamp
  function balanceOfNFTAt(
    uint256 _tokenId,
    uint256 _t
  ) external view returns (uint256);

  /// @notice Get locked balance information for a token
  function locked(
    uint256 _tokenId
  ) external view returns (LockedBalance memory);

  /// @notice Create a new lock
  function createLock(
    uint256 _value,
    uint256 _lockDuration
  ) external returns (uint256);

  /// @notice Increase the amount of an existing lock
  function increaseAmount(uint256 _tokenId, uint256 _value) external;

  /// @notice Increase the unlock time of an existing lock
  function increaseUnlockTime(
    uint256 _tokenId,
    uint256 _lockDuration
  ) external;

  /// @notice Withdraw tokens from an expired lock
  function withdraw(uint256 _tokenId) external;

  /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Address of token (VELO) used to create a veNFT
  function token() external view returns (address);

  /// @notice Address of Velodrome Team multisig
  function team() external view returns (address);

  /// @dev Current count of token
  function tokenId() external view returns (uint256);

  /*///////////////////////////////////////////////////////////////
                            GAUGE VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Calculate total voting power at current timestamp
  /// @return Total voting power at current timestamp
  function totalSupply() external view returns (uint256);

  /// @notice Calculate total voting power at a given timestamp
  /// @param _t Timestamp to query total voting power
  /// @return Total voting power at given timestamp
  function totalSupplyAt(uint256 _t) external view returns (uint256);

  /*///////////////////////////////////////////////////////////////
                             DAO VOTING LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Delegate votes from `msg.sender` to `delegatee`
  /// @param delegator The address to get votes from current checkpoints
  /// @param delegatee The address to give votes to current checkpoints
  function delegate(uint256 delegator, uint256 delegatee) external;

  /// @notice Delegate votes by signature
  /// @param delegator The address to get votes from current checkpoints
  /// @param delegatee The address to give votes to current checkpoints
  /// @param nonce used to prevent replay attacks
  /// @param expiry time when signature expires
  /// @param v The recovery byte of the signature
  /// @param r Half of the ECDSA signature pair
  /// @param s Half of the ECDSA signature pair
  function delegateBySig(
    uint256 delegator,
    uint256 delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;
}
