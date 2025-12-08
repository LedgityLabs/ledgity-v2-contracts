// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AdministeredUpgradable } from "src/protocol-v2/modules/AdministeredUpgradable.sol";
// Libraries
import { BalanceLogicLibrary } from "src/protocol-v2/libraries/BalanceLogicLibrary.sol";
import { SafeCastLibrary } from "src/protocol-v2/libraries/SafeCastLibrary.sol";
// Extensions
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// Interfaces
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";
import { IStakingRewardsDistributor } from "src/protocol-v2/interfaces/IStakingRewardsDistributor.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title Ledgity Staking Positions
 * @notice Staking position NFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
 * @notice Voting power has a weight depending on time, so that users are committed to the future of the protocol
 * @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
 * @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
 * @author Modified from Velodrome (https://github.com/velodrome-finance/contracts/blob/main/contracts/VotingEscrow.sol)
 * @author Ledgity, vBlackwhale (https://github.com/vblackwhale)
 *
 * @dev Vote weight decays linearly over time. Lock time cannot be more than `maxTime` (configurable, default 4 years).
 */
contract StakingPositions is
  IStakingPositions,
  ReentrancyGuard,
  AdministeredUpgradable
{
  using SafeERC20 for IERC20;
  using SafeCastLibrary for uint256;
  using SafeCastLibrary for int128;

  /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

  uint256 internal constant WEEK = 1 weeks;
  string public constant name = "Ledgity Staking Positions";
  string public constant symbol = "lsNFT";
  uint8 public constant decimals = 18;

  /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  address public token;

  address public rewardsDistributor;
  /// @inheritdoc IStakingPositions
  address public artProxy;
  /// @inheritdoc IStakingPositions
  uint256 public tokenId;
  /// @inheritdoc IStakingPositions
  uint256 public epoch;
  /// @inheritdoc IStakingPositions
  uint256 public supply;
  /// @notice Maximum lock time in seconds (configurable by owner)
  uint256 public maxTime = 4 * 365 * 86400;
  /// @notice Maximum lock time as int128 for calculations
  int128 public iMaxTime = 4 * 365 * 86400;
  /// @notice Breaker to allow owner to unlock all positions
  bool public breaker;

  mapping(uint256 epoch => GlobalPoint globalPoint)
    internal pointHistory;
  mapping(bytes4 interfaceId => bool supported)
    internal supportedInterfaces;
  mapping(uint256 tokenId => address owner) internal idToOwner;
  mapping(address owner => uint256 count)
    internal ownerToNFTokenCount;
  mapping(uint256 tokenId => address approved) internal idToApprovals;
  mapping(address owner => mapping(address operator => bool approved))
    internal ownerToOperators;
  mapping(uint256 tokenId => uint256 blockNumber)
    internal ownershipChange;
  /// @inheritdoc IStakingPositions
  mapping(address owner => mapping(uint256 index => uint256 tokenId))
    public ownerToNFTokenIdList;
  mapping(uint256 tokenId => uint256 index)
    internal tokenToOwnerIndex;
  mapping(uint256 tokenId => LockedBalance balance) internal locked;
  mapping(uint256 tokenId => UserPoint[1000000000] points)
    internal userPointHistory;
  mapping(uint256 tokenId => uint256 epoch) public userPointEpoch;
  /// @inheritdoc IStakingPositions
  mapping(uint256 timestamp => int128 change) public slopeChanges;

  /*//////////////////////////////////////////////////////////////
                               INITIALIZER
    //////////////////////////////////////////////////////////////*/

  constructor() {
    _disableInitializers();
  }

  /// @param token_ `LDY` token address
  function initialize(
    address token_,
    address rewardsDistributor_,
    uint256 maxTime_,
    address globalOwner_,
    address globalPause_,
    address globalAccessList_
  ) public initializer {
    maxTime = maxTime_;
    iMaxTime = int128(uint128(maxTime_));
    token = token_;
    rewardsDistributor = rewardsDistributor_;

    pointHistory[0].timestamp = block.timestamp;

    /// @dev ERC165 interface ID of ERC165
    supportedInterfaces[0x01ffc9a7] = true;
    /// @dev ERC165 interface ID of ERC721
    supportedInterfaces[0x80ac58cd] = true;
    /// @dev ERC165 interface ID of ERC721Metadata
    supportedInterfaces[0x5b5e139f] = true;
    /// @dev ERC165 interface ID of ERC4906
    supportedInterfaces[0x49064906] = true;
    /// @dev ERC165 interface ID of ERC6372
    supportedInterfaces[0xda287a1d] = true;

    // mint-ish
    emit Transfer(address(0), address(this), tokenId);
    // burn-ish
    emit Transfer(address(this), address(0), tokenId);

    __AdministeredUpgradable_init(
      globalOwner_,
      globalPause_,
      globalAccessList_
    );
  }

  /*//////////////////////////////////////////////////////////////
                              READ FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function tokenURI(
    uint256 _tokenId
  ) external view returns (string memory) {
    if (idToOwner[_tokenId] == address(0)) revert NonExistentToken();
    return IERC721Metadata(artProxy).tokenURI(_tokenId);
  }

  /// @inheritdoc IStakingPositions
  function ownerOf(uint256 _tokenId) public view returns (address) {
    return idToOwner[_tokenId];
  }

  /// @inheritdoc IStakingPositions
  function balanceOf(address _owner) external view returns (uint256) {
    return getUserTotalVotingPowerAt(_owner, block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function balanceOfAccountNFT(
    address _owner
  ) external view returns (uint256) {
    return ownerToNFTokenCount[_owner];
  }

  /// @inheritdoc IStakingPositions
  function getApproved(
    uint256 _tokenId
  ) external view returns (address) {
    return idToApprovals[_tokenId];
  }

  /// @inheritdoc IStakingPositions
  function isApprovedForAll(
    address _owner,
    address _operator
  ) external view returns (bool) {
    return (ownerToOperators[_owner])[_operator];
  }

  /// @inheritdoc IStakingPositions
  function isApprovedOrOwner(
    address _spender,
    uint256 _tokenId
  ) public view returns (bool) {
    address owner = idToOwner[_tokenId];
    bool spenderIsOwner = owner == _spender;
    bool spenderIsApproved = _spender == idToApprovals[_tokenId];
    bool spenderIsApprovedForAll = (ownerToOperators[owner])[
      _spender
    ];
    return
      spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
  }

  /// @inheritdoc IStakingPositions
  function supportsInterface(
    bytes4 _interfaceID
  ) external view returns (bool) {
    return supportedInterfaces[_interfaceID];
  }

  /// @inheritdoc IStakingPositions
  function getLockedBalance(
    uint256 _tokenId
  ) external view returns (LockedBalance memory) {
    return locked[_tokenId];
  }

  /// @inheritdoc IStakingPositions
  function getUserPointHistory(
    uint256 _tokenId,
    uint256 _epoch
  ) external view returns (UserPoint memory) {
    return userPointHistory[_tokenId][_epoch];
  }

  /// @inheritdoc IStakingPositions
  function getPointHistory(
    uint256 _epoch
  ) external view returns (GlobalPoint memory) {
    return pointHistory[_epoch];
  }

  /// @inheritdoc IStakingPositions
  function balanceOfNFT(
    uint256 _tokenId
  ) public view returns (uint256) {
    if (ownershipChange[_tokenId] == block.number) return 0;
    return balanceOfNFTAt(_tokenId, block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function balanceOfNFTAt(
    uint256 _tokenId,
    uint256 _timestamp
  ) public view returns (uint256) {
    return
      BalanceLogicLibrary.balanceOfNFTAt(
        userPointEpoch,
        userPointHistory,
        _tokenId,
        _timestamp
      );
  }

  /// @inheritdoc IStakingPositions
  function totalSupply() external view returns (uint256) {
    return totalSupplyAt(block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function totalSupplyAt(
    uint256 _timestamp
  ) public view returns (uint256) {
    return
      BalanceLogicLibrary.supplyAt(
        slopeChanges,
        pointHistory,
        epoch,
        _timestamp
      );
  }

  /// @inheritdoc IStakingPositions
  function getUserNFTs(
    address _user
  ) external view returns (IStakingPositions.NFTData[] memory) {
    uint256 userBalance = ownerToNFTokenCount[_user];
    IStakingPositions.NFTData[]
      memory nftData = new IStakingPositions.NFTData[](userBalance);

    for (uint256 i; i < userBalance; i++) {
      uint256 currentTokenId = ownerToNFTokenIdList[_user][i];
      nftData[i] = IStakingPositions.NFTData({
        tokenId: currentTokenId,
        locked: locked[currentTokenId],
        votingPower: balanceOfNFT(currentTokenId),
        votingPowerAt: block.timestamp,
        owner: _user
      });
    }

    return nftData;
  }

  /// @inheritdoc IStakingPositions
  function getUserTotalVotingPower(
    address _user
  ) external view returns (uint256) {
    return getUserTotalVotingPowerAt(_user, block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function getUserTotalVotingPowerAt(
    address _user,
    uint256 _timestamp
  ) public view returns (uint256) {
    uint256 userBalance = ownerToNFTokenCount[_user];
    uint256 totalVotingPower = 0;

    for (uint256 i; i < userBalance; i++) {
      uint256 currentTokenId = ownerToNFTokenIdList[_user][i];
      totalVotingPower += balanceOfNFTAt(currentTokenId, _timestamp);
    }

    return totalVotingPower;
  }

  /*//////////////////////////////////////////////////////////////
                              READ INTERNAL
    //////////////////////////////////////////////////////////////*/

  function _isContract(address account) internal view returns (bool) {
    // This method relies on extcodesize, which returns 0 for contracts in
    // construction, since the code is only stored at the end of the
    // constructor execution.
    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }

  /*//////////////////////////////////////////////////////////////
                              NFT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function approve(
    address _approved,
    uint256 _tokenId
  ) external whenNotPaused {
    address owner = idToOwner[_tokenId];
    // Throws if `_tokenId` is not a valid NFT
    if (owner == address(0)) revert ZeroAddress();
    // Throws if `_approved` is the current owner
    if (owner == _approved) revert SameAddress();
    // Check requirements
    bool senderIsOwner = (idToOwner[_tokenId] == msg.sender);
    bool senderIsApprovedForAll = (ownerToOperators[owner])[
      msg.sender
    ];
    if (!senderIsOwner && !senderIsApprovedForAll)
      revert NotApprovedOrOwner();
    // Set the approval
    idToApprovals[_tokenId] = _approved;
    emit Approval(owner, _approved, _tokenId);
  }

  /// @inheritdoc IStakingPositions
  function setApprovalForAll(
    address _operator,
    bool _approved
  ) external whenNotPaused {
    // Throws if `_operator` is the `msg.sender`
    if (_operator == msg.sender) revert SameAddress();
    ownerToOperators[msg.sender][_operator] = _approved;
    emit ApprovalForAll(msg.sender, _operator, _approved);
  }

  /* TRANSFER FUNCTIONS */

  /// @inheritdoc IStakingPositions
  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external whenNotPaused notRestricted(_from) notRestricted(_to) {
    _transferFrom(_from, _to, _tokenId, msg.sender);
  }

  /// @inheritdoc IStakingPositions
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external whenNotPaused notRestricted(_from) notRestricted(_to) {
    safeTransferFrom(_from, _to, _tokenId, "");
  }

  /// @inheritdoc IStakingPositions
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes memory _data
  ) public whenNotPaused notRestricted(_from) notRestricted(_to) {
    _transferFrom(_from, _to, _tokenId, msg.sender);

    if (_isContract(_to)) {
      // Throws if transfer destination is a contract which does not implement 'onERC721Received'
      try
        IERC721Receiver(_to).onERC721Received(
          msg.sender,
          _from,
          _tokenId,
          _data
        )
      returns (bytes4 response) {
        if (
          response != IERC721Receiver(_to).onERC721Received.selector
        ) {
          revert ERC721ReceiverRejectedTokens();
        }
      } catch (bytes memory reason) {
        if (reason.length == 0) {
          revert ERC721TransferToNonERC721ReceiverImplementer();
        } else {
          assembly {
            revert(add(32, reason), mload(reason))
          }
        }
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                              POSITION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function checkpoint() external nonReentrant whenNotPaused {
    _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
  }

  /// @inheritdoc IStakingPositions
  function depositFor(
    uint256 _tokenId,
    uint256 _value
  ) external nonReentrant whenNotPaused notRestricted(msg.sender) {
    _increaseAmountFor(
      _tokenId,
      _value,
      DepositType.DEPOSIT_FOR_TYPE
    );
  }

  /// @inheritdoc IStakingPositions
  function createLock(
    uint256 _value,
    uint256 _lockDuration
  )
    external
    nonReentrant
    whenNotPaused
    notRestricted(msg.sender)
    returns (uint256)
  {
    return _createLock(_value, _lockDuration, msg.sender);
  }

  /// @inheritdoc IStakingPositions
  function increaseAmount(
    uint256 _tokenId,
    uint256 _value
  ) external nonReentrant whenNotPaused notRestricted(msg.sender) {
    if (!isApprovedOrOwner(msg.sender, _tokenId))
      revert NotApprovedOrOwner();
    _increaseAmountFor(
      _tokenId,
      _value,
      DepositType.INCREASE_LOCK_AMOUNT
    );
  }

  /// @inheritdoc IStakingPositions
  function increaseUnlockTime(
    uint256 _tokenId,
    uint256 _lockDuration
  ) external nonReentrant whenNotPaused notRestricted(msg.sender) {
    if (!isApprovedOrOwner(msg.sender, _tokenId))
      revert NotApprovedOrOwner();

    LockedBalance memory oldLocked = locked[_tokenId];

    uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) *
      WEEK; // Locktime is rounded down to weeks

    if (oldLocked.end <= block.timestamp) revert LockExpired();
    if (oldLocked.amount <= 0) revert NoLockFound();
    if (unlockTime <= oldLocked.end) revert LockDurationNotInFuture();
    if (block.timestamp + maxTime < unlockTime)
      revert LockDurationTooLong();

    _depositFor(
      _tokenId,
      0,
      unlockTime,
      oldLocked,
      DepositType.INCREASE_UNLOCK_TIME
    );

    emit MetadataUpdate(_tokenId);
  }

  /// @inheritdoc IStakingPositions
  function withdraw(
    uint256 _tokenId
  ) external nonReentrant whenNotPaused notRestricted(msg.sender) {
    if (!isApprovedOrOwner(msg.sender, _tokenId))
      revert NotApprovedOrOwner();

    LockedBalance memory oldLocked = locked[_tokenId];

    if (block.timestamp < oldLocked.end && !breaker)
      revert LockNotExpired();
    uint256 value = oldLocked.amount.toUint256();

    // Claim potential rewards before the token is burned
    IStakingRewardsDistributor(rewardsDistributor).claimOnWithdrawal(
      _tokenId,
      msg.sender
    );

    // Burn the NFT
    _burn(_tokenId);
    locked[_tokenId] = LockedBalance(0, 0);
    uint256 supplyBefore = supply;
    supply = supplyBefore - value;

    // oldLocked can have either expired <= timestamp or zero end
    // oldLocked has only 0 end
    // Both can have >= 0 amount
    _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0));

    IERC20(token).safeTransfer(msg.sender, value);

    emit Withdraw(msg.sender, _tokenId, value, block.timestamp);
    emit Supply(supplyBefore, supplyBefore - value);
  }

  /*//////////////////////////////////////////////////////////////
                              NFT INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  function _transferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    address _sender
  ) internal {
    // Check requirements
    if (!isApprovedOrOwner(_sender, _tokenId))
      revert NotApprovedOrOwner();
    // Clear approval. Throws if `_from` is not the current owner
    if (idToOwner[_tokenId] != _from) revert NotOwner();
    delete idToApprovals[_tokenId];
    // Remove NFT. Throws if `_tokenId` is not a valid NFT
    _removeTokenFrom(_from, _tokenId);
    // Add NFT
    _addTokenTo(_to, _tokenId);
    // Set the block of ownership transfer (for Flash NFT protection)
    ownershipChange[_tokenId] = block.number;
    // Log the transfer
    emit Transfer(_from, _to, _tokenId);
  }

  /// @dev Add a NFT to an index mapping to a given address
  /// @param _to address of the receiver
  /// @param _tokenId uint ID Of the token to be added
  function _addTokenToOwnerList(
    address _to,
    uint256 _tokenId
  ) internal {
    uint256 currentCount = ownerToNFTokenCount[_to];

    ownerToNFTokenIdList[_to][currentCount] = _tokenId;
    tokenToOwnerIndex[_tokenId] = currentCount;
  }

  /// @dev Add a NFT to a given address
  ///      Throws if `_tokenId` is owned by someone.
  function _addTokenTo(address _to, uint256 _tokenId) internal {
    // Throws if `_tokenId` is owned by someone
    assert(idToOwner[_tokenId] == address(0));
    // Change the owner
    idToOwner[_tokenId] = _to;
    // Update owner token index tracking
    _addTokenToOwnerList(_to, _tokenId);
    // Change count tracking
    ownerToNFTokenCount[_to] += 1;
  }

  /// @dev Function to mint tokens
  ///      Throws if `_to` is zero address.
  ///      Throws if `_tokenId` is owned by someone.
  /// @param _to The address that will receive the minted tokens.
  /// @param _tokenId The token id to mint.
  /// @return A boolean that indicates if the operation was successful.
  function _mint(
    address _to,
    uint256 _tokenId
  ) internal returns (bool) {
    // Throws if `_to` is zero address
    assert(_to != address(0));
    // Add NFT. Throws if `_tokenId` is owned by someone
    _addTokenTo(_to, _tokenId);
    emit Transfer(address(0), _to, _tokenId);
    return true;
  }

  /// @dev Remove a NFT from an index mapping to a given address
  /// @param _from address of the sender
  /// @param _tokenId uint ID Of the token to be removed
  function _removeTokenFromOwnerList(
    address _from,
    uint256 _tokenId
  ) internal {
    // Delete
    uint256 currentCount = ownerToNFTokenCount[_from] - 1;
    uint256 currentIndex = tokenToOwnerIndex[_tokenId];

    if (currentCount == currentIndex) {
      // update ownerToNFTokenIdList
      ownerToNFTokenIdList[_from][currentCount] = 0;
      // update tokenToOwnerIndex
      tokenToOwnerIndex[_tokenId] = 0;
    } else {
      uint256 lastTokenId = ownerToNFTokenIdList[_from][currentCount];

      // Add
      // update ownerToNFTokenIdList
      ownerToNFTokenIdList[_from][currentIndex] = lastTokenId;
      // update tokenToOwnerIndex
      tokenToOwnerIndex[lastTokenId] = currentIndex;

      // Delete
      // update ownerToNFTokenIdList
      ownerToNFTokenIdList[_from][currentCount] = 0;
      // update tokenToOwnerIndex
      tokenToOwnerIndex[_tokenId] = 0;
    }
  }

  /// @dev Remove a NFT from a given address
  ///      Throws if `_from` is not the current owner.
  function _removeTokenFrom(
    address _from,
    uint256 _tokenId
  ) internal {
    // Throws if `_from` is not the current owner
    assert(idToOwner[_tokenId] == _from);
    // Change the owner
    idToOwner[_tokenId] = address(0);
    // Update owner token index tracking
    _removeTokenFromOwnerList(_from, _tokenId);
    // Change count tracking
    ownerToNFTokenCount[_from] -= 1;
  }

  /// @dev Must be called prior to updating `LockedBalance`
  function _burn(uint256 _tokenId) internal {
    if (!isApprovedOrOwner(msg.sender, _tokenId))
      revert NotApprovedOrOwner();
    address owner = idToOwner[_tokenId];

    // Clear approval
    delete idToApprovals[_tokenId];
    // Remove token
    _removeTokenFrom(owner, _tokenId);
    emit Transfer(owner, address(0), _tokenId);
  }

  /*//////////////////////////////////////////////////////////////
                             POSITION INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Record global and per-user data to checkpoints. Used by VotingEscrow system.
  /// @param _tokenId NFT token ID. No user checkpoint if 0
  /// @param _oldLocked Pevious locked amount / end lock time for the user
  /// @param _newLocked New locked amount / end lock time for the user
  function _checkpoint(
    uint256 _tokenId,
    LockedBalance memory _oldLocked,
    LockedBalance memory _newLocked
  ) internal {
    UserPoint memory uOld;
    UserPoint memory uNew;
    int128 oldDslope = 0;
    int128 newDslope = 0;
    uint256 _epoch = epoch;

    if (_tokenId != 0) {
      // Calculate slopes and biases
      // Kept at zero when they have to
      if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
        uOld.slope = _oldLocked.amount / iMaxTime;
        uOld.bias =
          uOld.slope *
          (_oldLocked.end - block.timestamp).toInt128();
      }
      if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
        uNew.slope = _newLocked.amount / iMaxTime;
        uNew.bias =
          uNew.slope *
          (_newLocked.end - block.timestamp).toInt128();
      }

      // Read values of scheduled changes in the slope
      // _oldLocked.end can be in the past and in the future
      // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
      oldDslope = slopeChanges[_oldLocked.end];
      if (_newLocked.end != 0) {
        if (_newLocked.end == _oldLocked.end) {
          newDslope = oldDslope;
        } else {
          newDslope = slopeChanges[_newLocked.end];
        }
      }
    }

    GlobalPoint memory lastPoint = GlobalPoint({
      bias: 0,
      slope: 0,
      timestamp: block.timestamp
    });
    if (_epoch > 0) {
      lastPoint = pointHistory[_epoch];
    }
    uint256 lastCheckpoint = lastPoint.timestamp;
    // If last point is already recorded in this block, slope=0
    // But that's ok b/c we know the block in such case

    // Go over weeks to fill history and calculate what the current point is
    {
      uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
      for (uint256 i; i < 255; ++i) {
        // Hopefully it won't happen that this won't get used in 5 years!
        // If it does, users will be able to withdraw but vote weight will be broken
        t_i += WEEK; // Initial value of t_i is always larger than the timestamp of the last point
        int128 d_slope = 0;
        if (t_i > block.timestamp) {
          t_i = block.timestamp;
        } else {
          d_slope = slopeChanges[t_i];
        }
        lastPoint.bias -=
          lastPoint.slope *
          (t_i - lastCheckpoint).toInt128();
        lastPoint.slope += d_slope;
        if (lastPoint.bias < 0) {
          // This can happen
          lastPoint.bias = 0;
        }
        if (lastPoint.slope < 0) {
          // This cannot happen - just in case
          lastPoint.slope = 0;
        }
        lastCheckpoint = t_i;
        lastPoint.timestamp = t_i;
        _epoch += 1;
        if (t_i == block.timestamp) {
          break;
        } else {
          pointHistory[_epoch] = lastPoint;
        }
      }
    }

    if (_tokenId != 0) {
      // If last point was in this block, the slope change has been applied already
      // But in such case we have 0 slope(s)
      lastPoint.slope += (uNew.slope - uOld.slope);
      lastPoint.bias += (uNew.bias - uOld.bias);
      if (lastPoint.slope < 0) {
        lastPoint.slope = 0;
      }
      if (lastPoint.bias < 0) {
        lastPoint.bias = 0;
      }
    }

    // If timestamp of last global point is the same, overwrite the last global point
    // Else record the new global point into history
    // Exclude epoch 0 (note: _epoch is always >= 1, see above)
    // Two possible outcomes:
    // Missing global checkpoints in prior weeks. In this case, _epoch = epoch + x, where x > 1
    // No missing global checkpoints, but timestamp != block.timestamp. Create new checkpoint.
    // No missing global checkpoints, but timestamp == block.timestamp. Overwrite last checkpoint.
    if (
      _epoch != 1 &&
      pointHistory[_epoch - 1].timestamp == block.timestamp
    ) {
      // _epoch = epoch + 1, so we do not increment epoch
      pointHistory[_epoch - 1] = lastPoint;
    } else {
      // more than one global point may have been written, so we update epoch
      epoch = _epoch;
      pointHistory[_epoch] = lastPoint;
    }

    if (_tokenId != 0) {
      // Schedule the slope changes (slope is going down)
      // We subtract new_user_slope from [_newLocked.end]
      // and add old_user_slope to [_oldLocked.end]
      if (_oldLocked.end > block.timestamp) {
        // oldDslope was <something> - uOld.slope, so we cancel that
        oldDslope += uOld.slope;
        if (_newLocked.end == _oldLocked.end) {
          oldDslope -= uNew.slope; // It was a new deposit, not extension
        }
        slopeChanges[_oldLocked.end] = oldDslope;
      }

      if (_newLocked.end > block.timestamp) {
        // update slope if new lock is greater than old lock
        if ((_newLocked.end > _oldLocked.end)) {
          newDslope -= uNew.slope; // old slope disappeared at this point
          slopeChanges[_newLocked.end] = newDslope;
        }
        // else: we recorded it already in oldDslope
      }
      // If timestamp of last user point is the same, overwrite the last user point
      // Else record the new user point into history
      // Exclude epoch 0
      uNew.timestamp = block.timestamp;
      uint256 userEpoch = userPointEpoch[_tokenId];
      if (
        userEpoch != 0 &&
        userPointHistory[_tokenId][userEpoch].timestamp ==
        block.timestamp
      ) {
        userPointHistory[_tokenId][userEpoch] = uNew;
      } else {
        userPointEpoch[_tokenId] = ++userEpoch;
        userPointHistory[_tokenId][userEpoch] = uNew;
      }
    }
  }

  /// @notice Deposit and lock tokens for a user
  /// @param _tokenId NFT that holds lock
  /// @param _value Amount to deposit
  /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
  /// @param _oldLocked Previous locked amount / timestamp
  /// @param _depositType The type of deposit
  function _depositFor(
    uint256 _tokenId,
    uint256 _value,
    uint256 _unlockTime,
    LockedBalance memory _oldLocked,
    DepositType _depositType
  ) internal {
    uint256 supplyBefore = supply;
    supply = supplyBefore + _value;

    // Set newLocked to _oldLocked without mangling memory
    LockedBalance memory newLocked;
    (newLocked.amount, newLocked.end) = (
      _oldLocked.amount,
      _oldLocked.end
    );

    // Adding to existing lock, or if a lock is expired - creating a new one
    newLocked.amount += _value.toInt128();
    if (_unlockTime != 0) {
      newLocked.end = _unlockTime;
    }
    locked[_tokenId] = newLocked;

    // Possibilities:
    // Both _oldLocked.end could be current or expired (>/< block.timestamp)
    // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
    // newLocked.end > block.timestamp (always)
    _checkpoint(_tokenId, _oldLocked, newLocked);

    if (_value != 0) {
      IERC20(token).safeTransferFrom(
        msg.sender,
        address(this),
        _value
      );
    }

    emit Deposit(
      msg.sender,
      _tokenId,
      _depositType,
      _value,
      newLocked.end,
      block.timestamp
    );
    emit Supply(supplyBefore, supplyBefore + _value);
  }

  /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
  /// @param _value Amount to deposit
  /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
  /// @param _to Address to deposit
  function _createLock(
    uint256 _value,
    uint256 _lockDuration,
    address _to
  ) internal returns (uint256) {
    uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) *
      WEEK; // Locktime is rounded down to weeks

    if (_value == 0) revert ZeroAmount();
    if (unlockTime <= block.timestamp)
      revert LockDurationNotInFuture();
    if (block.timestamp + maxTime < unlockTime)
      revert LockDurationTooLong();

    uint256 _tokenId = ++tokenId;
    _mint(_to, _tokenId);

    _depositFor(
      _tokenId,
      _value,
      unlockTime,
      locked[_tokenId],
      DepositType.CREATE_LOCK_TYPE
    );

    // Notify rewards distributor of new lock creation
    IStakingRewardsDistributor(rewardsDistributor).onLockCreated(
      _tokenId
    );

    return _tokenId;
  }

  function _increaseAmountFor(
    uint256 _tokenId,
    uint256 _value,
    DepositType _depositType
  ) internal {
    LockedBalance memory oldLocked = locked[_tokenId];

    if (_value == 0) revert ZeroAmount();
    if (oldLocked.amount <= 0) revert NoLockFound();
    if (oldLocked.end <= block.timestamp) revert LockExpired();

    _depositFor(_tokenId, _value, 0, oldLocked, _depositType);

    emit MetadataUpdate(_tokenId);
  }

  /*//////////////////////////////////////////////////////////////
                              OWNER/ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function setArtProxy(address _proxy) external onlyOwner {
    artProxy = _proxy;
    emit BatchMetadataUpdate(0, type(uint256).max);
  }

  /// @inheritdoc IStakingPositions
  function setMaxTime(uint256 _maxTime) external onlyOwner {
    maxTime = _maxTime;
    iMaxTime = int128(uint128(_maxTime));
  }

  /// @inheritdoc IStakingPositions
  function unlockAll() external onlyOwner {
    breaker = true;
    emit BreakerActivated();
  }
}
