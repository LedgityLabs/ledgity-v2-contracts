// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// Libraries
import { BalanceLogicLibrary } from "src/protocol-v2/libraries/BalanceLogicLibrary.sol";
import { SafeCastLibrary } from "src/protocol-v2/libraries/SafeCastLibrary.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// Interfaces
import { IStakingPositions } from "src/protocol-v2/interfaces/IStakingPositions.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title Ledgity DAO Voting NFT
 * @notice voting NFT implementation that escrows ERC-20 tokens in the form of an ERC-721 NFT
 * @notice Votes have a weight depending on time, so that users are committed to the future of (whatever they are voting for)
 * @author Modified from Solidly (https://github.com/solidlyexchange/solidly/blob/master/contracts/ve.sol)
 * @author Modified from Curve (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
 * @author Modified from Velodrome (https://github.com/velodrome-finance/contracts/blob/main/contracts/VotingEscrow.sol)
 * @author Ledgity, vBlackwhale (https://github.com/vblackwhale)
 *
 * @dev Vote weight decays linearly over time. Lock time cannot be more than `MAXTIME` (4 years).
 */
contract StakingPositions is
  IStakingPositions,
  ReentrancyGuard,
  Ownable
{
  using SafeERC20 for IERC20;
  using SafeCastLibrary for uint256;
  using SafeCastLibrary for int128;
  /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  address public immutable token;
  /// @inheritdoc IStakingPositions
  address public artProxy;

  mapping(uint256 => GlobalPoint) internal _pointHistory; // epoch -> unsigned global point

  /// @dev Mapping of interface id to bool about whether or not it's supported
  mapping(bytes4 => bool) internal supportedInterfaces;

  /// @inheritdoc IStakingPositions
  uint256 public tokenId;

  /// @param _token `LDY` token address
  constructor(address _token) {
    token = _token;

    _pointHistory[0].ts = block.timestamp;

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
  }

  /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

  string public constant name = "Ledgity Vote NFT";
  string public constant symbol = "lvNFT";
  uint8 public constant decimals = 18;

  function setArtProxy(address _proxy) external onlyOwner {
    artProxy = _proxy;
    emit BatchMetadataUpdate(0, type(uint256).max);
  }

  /// @inheritdoc IStakingPositions
  function tokenURI(
    uint256 _tokenId
  ) external view returns (string memory) {
    if (_ownerOf(_tokenId) == address(0)) revert NonExistentToken();
    return IERC721Metadata(artProxy).tokenURI(_tokenId);
  }

  /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @dev Mapping from NFT ID to the address that owns it.
  mapping(uint256 => address) internal idToOwner;

  /// @dev Mapping from owner address to count of his tokens.
  mapping(address => uint256) internal ownerToNFTokenCount;

  function _ownerOf(
    uint256 _tokenId
  ) internal view returns (address) {
    return idToOwner[_tokenId];
  }

  /// @inheritdoc IStakingPositions
  function ownerOf(uint256 _tokenId) external view returns (address) {
    return _ownerOf(_tokenId);
  }

  /// @inheritdoc IStakingPositions
  function balanceOf(address _owner) external view returns (uint256) {
    return ownerToNFTokenCount[_owner];
  }

  /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @dev Mapping from NFT ID to approved address.
  mapping(uint256 => address) internal idToApprovals;

  /// @dev Mapping from owner address to mapping of operator addresses.
  mapping(address => mapping(address => bool))
    internal ownerToOperators;

  mapping(uint256 => uint256) internal ownershipChange;

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
  ) external view returns (bool) {
    return _isApprovedOrOwner(_spender, _tokenId);
  }

  function _isApprovedOrOwner(
    address _spender,
    uint256 _tokenId
  ) internal view returns (bool) {
    address owner = _ownerOf(_tokenId);
    bool spenderIsOwner = owner == _spender;
    bool spenderIsApproved = _spender == idToApprovals[_tokenId];
    bool spenderIsApprovedForAll = (ownerToOperators[owner])[
      _spender
    ];
    return
      spenderIsOwner || spenderIsApproved || spenderIsApprovedForAll;
  }

  /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function approve(address _approved, uint256 _tokenId) external {
    address sender = _msgSender();
    address owner = _ownerOf(_tokenId);
    // Throws if `_tokenId` is not a valid NFT
    if (owner == address(0)) revert ZeroAddress();
    // Throws if `_approved` is the current owner
    if (owner == _approved) revert SameAddress();
    // Check requirements
    bool senderIsOwner = (_ownerOf(_tokenId) == sender);
    bool senderIsApprovedForAll = (ownerToOperators[owner])[sender];
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
  ) external {
    address sender = _msgSender();
    // Throws if `_operator` is the `msg.sender`
    if (_operator == sender) revert SameAddress();
    ownerToOperators[sender][_operator] = _approved;
    emit ApprovalForAll(sender, _operator, _approved);
  }

  /* TRANSFER FUNCTIONS */

  function _transferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    address _sender
  ) internal {
    // Check requirements
    if (!_isApprovedOrOwner(_sender, _tokenId))
      revert NotApprovedOrOwner();
    // Clear approval. Throws if `_from` is not the current owner
    if (_ownerOf(_tokenId) != _from) revert NotOwner();
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

  /// @inheritdoc IStakingPositions
  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external {
    _transferFrom(_from, _to, _tokenId, _msgSender());
  }

  /// @inheritdoc IStakingPositions
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external {
    safeTransferFrom(_from, _to, _tokenId, "");
  }

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

  /// @inheritdoc IStakingPositions
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes memory _data
  ) public {
    address sender = _msgSender();
    _transferFrom(_from, _to, _tokenId, sender);

    if (_isContract(_to)) {
      // Throws if transfer destination is a contract which does not implement 'onERC721Received'
      try
        IERC721Receiver(_to).onERC721Received(
          sender,
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
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  function supportsInterface(
    bytes4 _interfaceID
  ) external view returns (bool) {
    return supportedInterfaces[_interfaceID];
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IStakingPositions
  mapping(address => mapping(uint256 => uint256))
    public ownerToNFTokenIdList;

  /// @dev Mapping from NFT ID to index of owner
  mapping(uint256 => uint256) internal tokenToOwnerIndex;

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
    assert(_ownerOf(_tokenId) == address(0));
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
    assert(_ownerOf(_tokenId) == _from);
    // Change the owner
    idToOwner[_tokenId] = address(0);
    // Update owner token index tracking
    _removeTokenFromOwnerList(_from, _tokenId);
    // Change count tracking
    ownerToNFTokenCount[_from] -= 1;
  }

  /// @dev Must be called prior to updating `LockedBalance`
  function _burn(uint256 _tokenId) internal {
    address sender = _msgSender();
    if (!_isApprovedOrOwner(sender, _tokenId))
      revert NotApprovedOrOwner();
    address owner = _ownerOf(_tokenId);

    // Clear approval
    delete idToApprovals[_tokenId];
    // Remove token
    _removeTokenFrom(owner, _tokenId);
    emit Transfer(owner, address(0), _tokenId);
  }

  /*//////////////////////////////////////////////////////////////
                             ESCROW STORAGE
    //////////////////////////////////////////////////////////////*/

  uint256 internal constant WEEK = 1 weeks;
  uint256 internal constant MAXTIME = 4 * 365 * 86400;
  int128 internal constant iMAXTIME = 4 * 365 * 86400;

  /// @inheritdoc IStakingPositions
  uint256 public epoch;
  /// @inheritdoc IStakingPositions
  uint256 public supply;

  mapping(uint256 => LockedBalance) internal _locked;
  mapping(uint256 => UserPoint[1000000000])
    internal _userPointHistory;
  mapping(uint256 => uint256) public userPointEpoch;
  /// @inheritdoc IStakingPositions
  mapping(uint256 => int128) public slopeChanges;

  /// @inheritdoc IStakingPositions
  function locked(
    uint256 _tokenId
  ) external view returns (LockedBalance memory) {
    return _locked[_tokenId];
  }

  /// @inheritdoc IStakingPositions
  function userPointHistory(
    uint256 _tokenId,
    uint256 _loc
  ) external view returns (UserPoint memory) {
    return _userPointHistory[_tokenId][_loc];
  }

  /// @inheritdoc IStakingPositions
  function pointHistory(
    uint256 _loc
  ) external view returns (GlobalPoint memory) {
    return _pointHistory[_loc];
  }

  /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
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
        uOld.slope = _oldLocked.amount / iMAXTIME;
        uOld.bias =
          uOld.slope *
          (_oldLocked.end - block.timestamp).toInt128();
      }
      if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
        uNew.slope = _newLocked.amount / iMAXTIME;
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
      ts: block.timestamp
    });
    if (_epoch > 0) {
      lastPoint = _pointHistory[_epoch];
    }
    uint256 lastCheckpoint = lastPoint.ts;
    // If last point is already recorded in this block, slope=0
    // But that's ok b/c we know the block in such case

    // Go over weeks to fill history and calculate what the current point is
    {
      uint256 t_i = (lastCheckpoint / WEEK) * WEEK;
      for (uint256 i = 0; i < 255; ++i) {
        // Hopefully it won't happen that this won't get used in 5 years!
        // If it does, users will be able to withdraw but vote weight will be broken
        t_i += WEEK; // Initial value of t_i is always larger than the ts of the last point
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
        lastPoint.ts = t_i;
        _epoch += 1;
        if (t_i == block.timestamp) {
          break;
        } else {
          _pointHistory[_epoch] = lastPoint;
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
      _epoch != 1 && _pointHistory[_epoch - 1].ts == block.timestamp
    ) {
      // _epoch = epoch + 1, so we do not increment epoch
      _pointHistory[_epoch - 1] = lastPoint;
    } else {
      // more than one global point may have been written, so we update epoch
      epoch = _epoch;
      _pointHistory[_epoch] = lastPoint;
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
      uNew.ts = block.timestamp;
      uint256 userEpoch = userPointEpoch[_tokenId];
      if (
        userEpoch != 0 &&
        _userPointHistory[_tokenId][userEpoch].ts == block.timestamp
      ) {
        _userPointHistory[_tokenId][userEpoch] = uNew;
      } else {
        userPointEpoch[_tokenId] = ++userEpoch;
        _userPointHistory[_tokenId][userEpoch] = uNew;
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
    _locked[_tokenId] = newLocked;

    // Possibilities:
    // Both _oldLocked.end could be current or expired (>/< block.timestamp)
    // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
    // newLocked.end > block.timestamp (always)
    _checkpoint(_tokenId, _oldLocked, newLocked);

    address from = _msgSender();
    if (_value != 0) {
      IERC20(token).safeTransferFrom(from, address(this), _value);
    }

    emit Deposit(
      from,
      _tokenId,
      _depositType,
      _value,
      newLocked.end,
      block.timestamp
    );
    emit Supply(supplyBefore, supplyBefore + _value);
  }

  /// @inheritdoc IStakingPositions
  function checkpoint() external nonReentrant {
    _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
  }

  /// @inheritdoc IStakingPositions
  function depositFor(
    uint256 _tokenId,
    uint256 _value
  ) external nonReentrant {
    _increaseAmountFor(
      _tokenId,
      _value,
      DepositType.DEPOSIT_FOR_TYPE
    );
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
    if (unlockTime > block.timestamp + MAXTIME)
      revert LockDurationTooLong();

    uint256 _tokenId = ++tokenId;
    _mint(_to, _tokenId);

    _depositFor(
      _tokenId,
      _value,
      unlockTime,
      _locked[_tokenId],
      DepositType.CREATE_LOCK_TYPE
    );
    return _tokenId;
  }

  /// @inheritdoc IStakingPositions
  function createLock(
    uint256 _value,
    uint256 _lockDuration
  ) external nonReentrant returns (uint256) {
    return _createLock(_value, _lockDuration, _msgSender());
  }

  function _increaseAmountFor(
    uint256 _tokenId,
    uint256 _value,
    DepositType _depositType
  ) internal {
    LockedBalance memory oldLocked = _locked[_tokenId];

    if (_value == 0) revert ZeroAmount();
    if (oldLocked.amount <= 0) revert NoLockFound();
    if (oldLocked.end <= block.timestamp) revert LockExpired();

    _depositFor(_tokenId, _value, 0, oldLocked, _depositType);

    emit MetadataUpdate(_tokenId);
  }

  /// @inheritdoc IStakingPositions
  function increaseAmount(
    uint256 _tokenId,
    uint256 _value
  ) external nonReentrant {
    if (!_isApprovedOrOwner(_msgSender(), _tokenId))
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
  ) external nonReentrant {
    if (!_isApprovedOrOwner(_msgSender(), _tokenId))
      revert NotApprovedOrOwner();

    LockedBalance memory oldLocked = _locked[_tokenId];

    uint256 unlockTime = ((block.timestamp + _lockDuration) / WEEK) *
      WEEK; // Locktime is rounded down to weeks

    if (oldLocked.end <= block.timestamp) revert LockExpired();
    if (oldLocked.amount <= 0) revert NoLockFound();
    if (unlockTime <= oldLocked.end) revert LockDurationNotInFuture();
    if (unlockTime > block.timestamp + MAXTIME)
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
  function withdraw(uint256 _tokenId) external nonReentrant {
    address sender = _msgSender();
    if (!_isApprovedOrOwner(sender, _tokenId))
      revert NotApprovedOrOwner();

    LockedBalance memory oldLocked = _locked[_tokenId];

    if (block.timestamp < oldLocked.end) revert LockNotExpired();
    uint256 value = oldLocked.amount.toUint256();

    // Burn the NFT
    _burn(_tokenId);
    _locked[_tokenId] = LockedBalance(0, 0);
    uint256 supplyBefore = supply;
    supply = supplyBefore - value;

    // oldLocked can have either expired <= timestamp or zero end
    // oldLocked has only 0 end
    // Both can have >= 0 amount
    _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0));

    IERC20(token).safeTransfer(sender, value);

    emit Withdraw(sender, _tokenId, value, block.timestamp);
    emit Supply(supplyBefore, supplyBefore - value);
  }

  /*///////////////////////////////////////////////////////////////
                           GAUGE VOTING STORAGE
    //////////////////////////////////////////////////////////////*/

  function _balanceOfNFTAt(
    uint256 _tokenId,
    uint256 _t
  ) internal view returns (uint256) {
    return
      BalanceLogicLibrary.balanceOfNFTAt(
        userPointEpoch,
        _userPointHistory,
        _tokenId,
        _t
      );
  }

  function _supplyAt(
    uint256 _timestamp
  ) internal view returns (uint256) {
    return
      BalanceLogicLibrary.supplyAt(
        slopeChanges,
        _pointHistory,
        epoch,
        _timestamp
      );
  }

  /// @inheritdoc IStakingPositions
  function balanceOfNFT(
    uint256 _tokenId
  ) public view returns (uint256) {
    if (ownershipChange[_tokenId] == block.number) return 0;
    return _balanceOfNFTAt(_tokenId, block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function balanceOfNFTAt(
    uint256 _tokenId,
    uint256 _t
  ) external view returns (uint256) {
    return _balanceOfNFTAt(_tokenId, _t);
  }

  /// @inheritdoc IStakingPositions
  function totalSupply() external view returns (uint256) {
    return _supplyAt(block.timestamp);
  }

  /// @inheritdoc IStakingPositions
  function totalSupplyAt(
    uint256 _timestamp
  ) external view returns (uint256) {
    return _supplyAt(_timestamp);
  }
}
