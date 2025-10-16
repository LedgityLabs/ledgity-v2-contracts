// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Extensions
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
// Modules
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICouncilMerkleDistributor } from "src/protocol-v2/interfaces/IMerkleDistributor.sol";

/**
 * @title CouncilMerkleDistributor
 * @notice Merkle distributor for council rewards with pausable root updates
 * @dev Allows claiming rewards via merkle proofs. Owner can update root during local pause.
 *
 * @author Ledgity, vBlackwhale (https://github.com/vblackwhale)
 */
contract CouncilMerkleDistributor is
  AdministeredUpgradable,
  ICouncilMerkleDistributor
{
  // ======== LIBS ======== //
  using SafeERC20 for IERC20;

  // ======== ERRORS ======== //

  /// @notice Thrown when attempting to claim an already claimed reward
  error AlreadyClaimed();

  /// @notice Thrown when the provided merkle proof is invalid
  error InvalidProof();

  /// @notice Thrown when attempting to update merkle root while not locally paused
  error CannotUpdateRootWhenNotPaused();

  // ======== STORAGE ======== //

  /// @notice The token distributed by this contract
  address public override token;

  /// @notice The merkle root of the merkle tree containing account balances available to claim
  bytes32 public override merkleRoot;

  /// @notice Bitmap tracking claimed rewards by index
  mapping(uint256 => uint256) private claimedBitMap;

  // ======== INITIALIZER ======== //

  /// @notice Disables initializers for the implementation contract
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the contract
  /// @param token_ Token to distribute
  /// @param merkleRoot_ Initial merkle root
  /// @param globalOwner_ GlobalOwner contract address
  /// @param globalPause_ GlobalPause contract address
  /// @param globalRestrict_ GlobalRestrict contract address
  function initialize(
    address token_,
    bytes32 merkleRoot_,
    address globalOwner_,
    address globalPause_,
    address globalRestrict_
  ) external initializer {
    __AdministeredUpgradable_init(
      globalOwner_,
      globalPause_,
      globalRestrict_
    );

    token = token_;
    merkleRoot = merkleRoot_;
  }

  // ======== VIEW FUNCTIONS ======== //

  /// @notice Returns true if the index has been claimed
  /// @param index Index to check in the merkle tree
  function isClaimed(
    uint256 index
  ) public view override returns (bool) {
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    uint256 claimedWord = claimedBitMap[claimedWordIndex];
    uint256 mask = (1 << claimedBitIndex);
    return claimedWord & mask == mask;
  }

  // ======== USER FUNCTIONS ======== //

  /// @notice Claim tokens with merkle proof
  /// @param index Index in the merkle tree
  /// @param account Address to receive tokens
  /// @param amount Amount to claim
  /// @param merkleProof Merkle proof for the claim
  function claim(
    uint256 index,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) public virtual override whenNotPaused notRestricted(account) {
    if (isClaimed(index)) revert AlreadyClaimed();

    // Verify the merkle proof.
    bytes32 node = keccak256(
      abi.encodePacked(index, account, amount)
    );
    if (!MerkleProof.verify(merkleProof, merkleRoot, node))
      revert InvalidProof();

    // Mark it claimed and send the token.
    uint256 claimedWordIndex = index / 256;
    uint256 claimedBitIndex = index % 256;
    claimedBitMap[claimedWordIndex] =
      claimedBitMap[claimedWordIndex] |
      (1 << claimedBitIndex);

    IERC20(token).safeTransfer(account, amount);

    emit Claimed(index, account, amount);
  }

  // ======== ADMIN FUNCTIONS ======== //

  /// @notice Updates merkle root (only when locally paused)
  /// @dev Allows combining multiple reward periods into one root
  /// @param newMerkleRoot New merkle root with combined rewards
  function updateMerkleRoot(
    bytes32 newMerkleRoot
  ) external onlyOwner {
    if (!isPausedLocal) revert CannotUpdateRootWhenNotPaused();

    bytes32 oldRoot = merkleRoot;
    merkleRoot = newMerkleRoot;

    emit MerkleRootUpdated(oldRoot, newMerkleRoot);
  }
}
