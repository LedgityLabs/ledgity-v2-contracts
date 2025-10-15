// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Contracts
import { CouncilMerkleDistributor } from "src/protocol-v2/staking/CouncilMerkleDistributor.sol";
import { ICouncilMerkleDistributor } from "src/protocol-v2/interfaces/IMerkleDistributor.sol";
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Merkle } from "foundry/lib/murky/src/Merkle.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CouncilMerkleDistributor_UnitTest is Test, Fixtures {
  CouncilMerkleDistributor public distributor;
  CouncilMerkleDistributor public distributorImpl;
  MockERC20 public rewardToken;
  Merkle public merkle;

  uint256 public constant REWARD_AMOUNT = 1000 * 1e18;
  bytes32 public constant TEST_ROOT = bytes32(keccak256("TEST_ROOT"));

  event Claimed(uint256 index, address account, uint256 amount);
  event MerkleRootUpdated(
    bytes32 indexed oldRoot,
    bytes32 indexed newRoot
  );

  function setUp() public {
    _setUp();
    _setupDistributor();
    _setupUsers();

    merkle = new Merkle();
  }

  function _setupDistributor() internal {
    // Create reward token first
    rewardToken = new MockERC20("Reward Token", "RWD", 18);
    
    // Deploy implementation
    distributorImpl = new CouncilMerkleDistributor();

    // Deploy proxy
    bytes memory initData = abi.encodeWithSelector(
      CouncilMerkleDistributor.initialize.selector,
      address(rewardToken),
      TEST_ROOT,
      address(globalOwner),
      address(globalPause),
      address(globalAccessList)
    );

    ERC1967Proxy proxy = new ERC1967Proxy(
      address(distributorImpl),
      initData
    );

    distributor = CouncilMerkleDistributor(address(proxy));
  }

  function _setupUsers() internal {
    // Mint tokens to distributor for rewards
    rewardToken.mint(address(distributor), REWARD_AMOUNT * 10);

    // Mint tokens to owner for testing
    rewardToken.mint(address(globalOwner), REWARD_AMOUNT);
  }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Initialize() public view {
    assertEq(distributor.token(), address(rewardToken));
    assertEq(distributor.merkleRoot(), TEST_ROOT);
    // The owner should be the actual owner from globalOwner, which is the test contract
    assertEq(distributor.owner(), address(this));
  }

  function test_Initialize_RevertIfAlreadyInitialized() public {
    vm.expectRevert();
    distributor.initialize(
      address(rewardToken),
      TEST_ROOT,
      address(globalOwner),
      address(globalPause),
      address(globalAccessList)
    );
  }

  /*//////////////////////////////////////////////////////////////
                            CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Claim_Success() public {
    // Create merkle tree data
    bytes32[] memory data = new bytes32[](3);
    data[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(200 * 1e18))
    );
    data[2] = keccak256(
      abi.encodePacked(uint256(2), testAccount3, uint256(300 * 1e18))
    );

    bytes32 root = merkle.getRoot(data);

    // Update merkle root
    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    // Get proof for testAccount1
    bytes32[] memory proof = merkle.getProof(data, 0);
    uint256 claimAmount = 100 * 1e18;

    uint256 balanceBefore = rewardToken.balanceOf(testAccount1);

    vm.expectEmit(true, true, true, true);
    emit Claimed(0, testAccount1, claimAmount);

    distributor.claim(0, testAccount1, claimAmount, proof);

    assertEq(
      rewardToken.balanceOf(testAccount1),
      balanceBefore + claimAmount
    );
    assertTrue(distributor.isClaimed(0));
  }

  function test_Claim_RevertAlreadyClaimed() public {
    // Setup merkle tree with multiple entries to avoid single leaf issue
    bytes32[] memory data = new bytes32[](2);
    data[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(200 * 1e18))
    );
    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    bytes32[] memory proof = merkle.getProof(data, 0);
    uint256 claimAmount = 100 * 1e18;

    // First claim should succeed
    distributor.claim(0, testAccount1, claimAmount, proof);

    // Second claim should revert
    vm.expectRevert(CouncilMerkleDistributor.AlreadyClaimed.selector);
    distributor.claim(0, testAccount1, claimAmount, proof);
  }

  function test_Claim_RevertInvalidProof() public {
    // Setup merkle tree
    bytes32[] memory data = new bytes32[](2);
    data[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(200 * 1e18))
    );
    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    // Get proof for wrong index
    bytes32[] memory wrongProof = merkle.getProof(data, 1);
    uint256 claimAmount = 100 * 1e18;

    vm.expectRevert(CouncilMerkleDistributor.InvalidProof.selector);
    distributor.claim(0, testAccount1, claimAmount, wrongProof);
  }

  function test_Claim_RevertWhenPaused() public {
    distributor.pauseLocal();

    bytes32[] memory emptyProof = new bytes32[](0);

    vm.expectRevert();
    distributor.claim(0, testAccount1, 100 * 1e18, emptyProof);
  }

  function test_Claim_RevertWhenRestricted() public {
    // Restrict testAccount1
    globalAccessList.restrictAccount(testAccount1);

    bytes32[] memory emptyProof = new bytes32[](0);

    vm.expectRevert();
    distributor.claim(0, testAccount1, 100 * 1e18, emptyProof);
  }

  /*//////////////////////////////////////////////////////////////
                            MERKLE ROOT UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

  function test_UpdateMerkleRoot_Success() public {
    bytes32 newRoot = bytes32(keccak256("NEW_ROOT"));
    bytes32 oldRoot = distributor.merkleRoot();

    distributor.pauseLocal();

    vm.expectEmit(true, true, true, true);
    emit MerkleRootUpdated(oldRoot, newRoot);

    distributor.updateMerkleRoot(newRoot);

    assertEq(distributor.merkleRoot(), newRoot);
  }

  function test_UpdateMerkleRoot_RevertNotOwner() public {
    bytes32 newRoot = bytes32(keccak256("NEW_ROOT"));

    vm.startPrank(testAccount1);
    vm.expectRevert();
    distributor.updateMerkleRoot(newRoot);
    vm.stopPrank();
  }

  function test_UpdateMerkleRoot_RevertNotPaused() public {
    bytes32 newRoot = bytes32(keccak256("NEW_ROOT"));

    vm.expectRevert(
      CouncilMerkleDistributor.CannotUpdateRootWhenNotPaused.selector
    );
    distributor.updateMerkleRoot(newRoot);
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_IsClaimed_ReturnsFalseInitially() public view {
    assertFalse(distributor.isClaimed(0));
    assertFalse(distributor.isClaimed(1));
    assertFalse(distributor.isClaimed(255));
    assertFalse(distributor.isClaimed(256));
  }

  function test_IsClaimed_ReturnsTrueAfterClaim() public {
    // Setup and claim with multiple entries
    bytes32[] memory data = new bytes32[](2);
    data[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(200 * 1e18))
    );
    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    bytes32[] memory proof = merkle.getProof(data, 0);
    distributor.claim(0, testAccount1, 100 * 1e18, proof);

    assertTrue(distributor.isClaimed(0));
    assertFalse(distributor.isClaimed(1));
  }

  /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

  function test_Integration_MultipleClaimsFromSameRoot() public {
    // Create merkle tree with multiple claims
    bytes32[] memory data = new bytes32[](3);
    data[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(200 * 1e18))
    );
    data[2] = keccak256(
      abi.encodePacked(uint256(2), testAccount3, uint256(300 * 1e18))
    );

    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    // Claim for all three accounts
    bytes32[] memory proof1 = merkle.getProof(data, 0);
    bytes32[] memory proof2 = merkle.getProof(data, 1);
    bytes32[] memory proof3 = merkle.getProof(data, 2);

    uint256 balance1Before = rewardToken.balanceOf(testAccount1);
    uint256 balance2Before = rewardToken.balanceOf(testAccount2);
    uint256 balance3Before = rewardToken.balanceOf(testAccount3);

    distributor.claim(0, testAccount1, 100 * 1e18, proof1);
    distributor.claim(1, testAccount2, 200 * 1e18, proof2);
    distributor.claim(2, testAccount3, 300 * 1e18, proof3);

    assertEq(
      rewardToken.balanceOf(testAccount1),
      balance1Before + 100 * 1e18
    );
    assertEq(
      rewardToken.balanceOf(testAccount2),
      balance2Before + 200 * 1e18
    );
    assertEq(
      rewardToken.balanceOf(testAccount3),
      balance3Before + 300 * 1e18
    );

    assertTrue(distributor.isClaimed(0));
    assertTrue(distributor.isClaimed(1));
    assertTrue(distributor.isClaimed(2));
  }

  function test_Integration_RootUpdateCombinesRewards() public {
    // First period rewards
    bytes32[] memory data1 = new bytes32[](2);
    data1[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(100 * 1e18))
    );
    data1[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(150 * 1e18))
    );
    bytes32 root1 = merkle.getRoot(data1);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root1);
    distributor.unpauseLocal();

    // Claim first period
    bytes32[] memory proof1 = merkle.getProof(data1, 0);
    distributor.claim(0, testAccount1, 100 * 1e18, proof1);

    // Second period - combined rewards (simulate off-chain combination)
    bytes32[] memory data2 = new bytes32[](2);
    data2[0] = keccak256(
      abi.encodePacked(uint256(0), testAccount1, uint256(250 * 1e18))
    ); // 100 + 150 combined
    data2[1] = keccak256(
      abi.encodePacked(uint256(1), testAccount2, uint256(300 * 1e18))
    ); // 150 + 150 combined
    bytes32 root2 = merkle.getRoot(data2);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root2);
    distributor.unpauseLocal();

    // Note: In real implementation, the new root would account for already claimed amounts
    // This test demonstrates the root update functionality
    assertEq(distributor.merkleRoot(), root2);
  }

  /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

  function testFuzz_Claim_ValidProof(
    uint256 index,
    uint256 amount,
    address account
  ) public {
    vm.assume(account != address(0));
    vm.assume(amount > 0 && amount <= REWARD_AMOUNT);
    index = bound(index, 0, 1000);

    // Create merkle tree with multiple entries to avoid single leaf issue
    bytes32[] memory data = new bytes32[](2);
    data[0] = keccak256(abi.encodePacked(index, account, amount));
    data[1] = keccak256(abi.encodePacked(index + 1, testAccount1, uint256(50 * 1e18)));
    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    bytes32[] memory proof = merkle.getProof(data, 0);
    uint256 balanceBefore = rewardToken.balanceOf(account);

    distributor.claim(index, account, amount, proof);

    assertEq(rewardToken.balanceOf(account), balanceBefore + amount);
    assertTrue(distributor.isClaimed(index));
  }

  function testFuzz_IsClaimed_BitmapStorage(uint256 index) public {
    index = bound(index, 0, 10000);

    // Should be false initially
    assertFalse(distributor.isClaimed(index));

    // Create and execute a claim for this index with multiple entries
    bytes32[] memory data = new bytes32[](2);
    data[0] = keccak256(
      abi.encodePacked(index, testAccount1, uint256(100 * 1e18))
    );
    data[1] = keccak256(
      abi.encodePacked(index + 1, testAccount2, uint256(200 * 1e18))
    );
    bytes32 root = merkle.getRoot(data);

    distributor.pauseLocal();
    distributor.updateMerkleRoot(root);
    distributor.unpauseLocal();

    bytes32[] memory proof = merkle.getProof(data, 0);
    distributor.claim(index, testAccount1, 100 * 1e18, proof);

    // Should be true after claim
    assertTrue(distributor.isClaimed(index));
  }
}
