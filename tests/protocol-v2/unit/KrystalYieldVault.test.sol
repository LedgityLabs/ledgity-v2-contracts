// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Contracts
import { ExternalYieldVault } from "src/protocol-v2/krystal/KrystalYieldVault.sol";
import { IKrystalVault, AssetLib } from "src/protocol-v2/krystal/IKrystalVault.sol";
// Libraries
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
// Fixtures
import { Fixtures } from "tests/protocol-v2/helpers/Fixtures.sol";
// Mock
import { MockERC20 } from "src/protocol-v1/mock/MockERC20.sol";

/**
 * @title MockKrystalVault
 * @notice Mock implementation of the Krystal vault for testing
 */
contract MockKrystalVault is IKrystalVault {
  MockERC20 public principalToken;
  uint256 public totalValue;
  uint256 private _totalSupply;
  uint256 public constant SHARES_PRECISION_VALUE = 1e18;

  mapping(address => uint256) private _balances;

  constructor(address principalToken_) {
    principalToken = MockERC20(principalToken_);
    totalValue = 0;
    _totalSupply = 0;
  }

  function SHARES_PRECISION() external pure returns (uint256) {
    return SHARES_PRECISION_VALUE;
  }

  function balanceOf(
    address account
  ) external view returns (uint256) {
    return _balances[account];
  }

  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  function getTotalValue() external view returns (uint256) {
    return totalValue;
  }

  function deposit(
    uint256 principalAmount,
    uint256 minShares
  ) external payable returns (uint256 returnShares) {
    principalToken.transferFrom(
      msg.sender,
      address(this),
      principalAmount
    );

    if (_totalSupply == 0) {
      returnShares = principalAmount * SHARES_PRECISION_VALUE;
    } else {
      returnShares = (principalAmount * _totalSupply) / totalValue;
    }

    if (returnShares < minShares) revert InsufficientShares();

    _balances[msg.sender] += returnShares;
    _totalSupply += returnShares;
    totalValue += principalAmount;

    emit VaultDeposit(
      address(0),
      msg.sender,
      principalAmount,
      returnShares
    );
  }

  function withdraw(
    uint256 shares,
    bool,
    uint256 minReturnAmount
  ) external returns (uint256 returnAmount) {
    if (shares > _balances[msg.sender]) revert InsufficientShares();

    returnAmount = (shares * totalValue) / _totalSupply;

    if (returnAmount < minReturnAmount)
      revert InsufficientReturnAmount();

    _balances[msg.sender] -= shares;
    _totalSupply -= shares;
    totalValue -= returnAmount;

    principalToken.transfer(msg.sender, returnAmount);

    emit VaultWithdraw(address(0), msg.sender, returnAmount, shares);
  }

  // Simulate yield accrual
  function simulateYield(uint256 yieldAmount) external {
    principalToken.mint(address(this), yieldAmount);
    totalValue += yieldAmount;
  }

  // Simulate loss
  function simulateLoss(uint256 lossAmount) external {
    totalValue -= lossAmount;
    principalToken.transfer(address(0xdead), lossAmount);
  }

  // Unused interface functions
  function vaultOwner() external pure returns (address) {
    return address(0);
  }

  function WETH() external pure returns (address) {
    return address(0);
  }

  function depositPrincipal(
    uint256
  ) external payable returns (uint256) {
    return 0;
  }

  function withdrawPrincipal(
    uint256,
    bool
  ) external pure returns (uint256) {
    return 0;
  }

  function harvest(
    AssetLib.Asset calldata,
    uint64,
    uint256
  ) external pure returns (AssetLib.Asset[] memory) {
    return new AssetLib.Asset[](0);
  }

  function harvestPrivate(
    AssetLib.Asset[] calldata,
    bool,
    uint64,
    uint256
  ) external {}

  function grantAdminRole(address) external {}

  function revokeAdminRole(address) external {}

  function sweepToken(address[] calldata) external {}

  function sweepERC721(
    address[] calldata,
    uint256[] calldata
  ) external {}

  function sweepERC1155(
    address[] calldata,
    uint256[] calldata
  ) external {}

  function transferOwnership(address) external {}

  function getInventory()
    external
    pure
    returns (AssetLib.Asset[] memory)
  {
    return new AssetLib.Asset[](0);
  }

  function getVaultConfig()
    external
    pure
    returns (bool, uint8, uint8, address, address[] memory, uint16)
  {
    return (true, 0, 0, address(0), new address[](0), 0);
  }
}

contract KrystalYieldVault_UnitTest is Test, Fixtures {
  ExternalYieldVault public vault;
  MockKrystalVault public krystalVault;
  MockERC20 public asset;

  uint256 public constant TEST_DEPOSIT_AMOUNT = 1000 * 1e6; // 1000 tokens (6 decimals)
  uint256 public constant SLIPPAGE_TOLERANCE = 100; // 1% in basis points
  uint256 public constant BASIS_POINTS = 10000;

  function setUp() public {
    _setUp();
    _setupVault();
  }

  function _setupVault() internal {
    // Create mock asset
    asset = new MockERC20("Test USDC", "USDC", 6);

    // Create mock Krystal vault
    krystalVault = new MockKrystalVault(address(asset));

    // Deploy ExternalYieldVault
    ExternalYieldVault impl = new ExternalYieldVault();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(impl),
      abi.encodeWithSelector(
        ExternalYieldVault.initialize.selector,
        address(krystalVault),
        "Krystal USDC Vault",
        "kUSDC",
        address(globalOwner),
        address(globalPause),
        address(globalAccessList),
        SLIPPAGE_TOLERANCE
      )
    );
    vault = ExternalYieldVault(address(proxy));

    // Setup test accounts with assets
    for (uint256 i = 0; i < users.length; i++) {
      asset.mint(users[i], INITIAL_BALANCE);
      vm.prank(users[i]);
      asset.approve(address(vault), type(uint256).max);
    }

    vm.label(address(vault), "ExternalYieldVault");
    vm.label(address(krystalVault), "MockKrystalVault");
    vm.label(address(asset), "TestAsset");
  }

  // ======== INITIALIZATION TESTS ======== //

  function test_initialization() public view {
    assertEq(address(vault.asset()), address(asset));
    assertEq(address(vault.krystalVault()), address(krystalVault));
    assertEq(vault.slippageToleranceDefault(), SLIPPAGE_TOLERANCE);
    assertEq(vault.BASIS_POINTS(), BASIS_POINTS);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.name(), "Krystal USDC Vault");
    assertEq(vault.symbol(), "kUSDC");
  }

  function test_initialization_zeroKrystalVault_reverts() public {
    ExternalYieldVault impl = new ExternalYieldVault();

    vm.expectRevert(ExternalYieldVault.ZeroAddress.selector);
    new ERC1967Proxy(
      address(impl),
      abi.encodeWithSelector(
        ExternalYieldVault.initialize.selector,
        address(0),
        "Test",
        "T",
        address(globalOwner),
        address(globalPause),
        address(globalAccessList),
        SLIPPAGE_TOLERANCE
      )
    );
  }

  // ======== VIEW FUNCTION TESTS ======== //

  function test_owner_returnsGlobalOwner() public view {
    assertEq(vault.owner(), globalOwner.owner());
  }

  function test_totalAssets_zeroWhenEmpty() public view {
    assertEq(vault.totalAssets(), 0);
  }

  function test_totalAssets_afterDeposit() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    assertEq(vault.totalAssets(), TEST_DEPOSIT_AMOUNT);
  }

  // ======== DEPOSIT TESTS ======== //

  function test_deposit_success() public {
    uint256 initialBalance = asset.balanceOf(testAccount1);

    vm.prank(testAccount1);
    uint256 shares = vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    assertEq(
      asset.balanceOf(testAccount1),
      initialBalance - TEST_DEPOSIT_AMOUNT
    );
    assertEq(vault.balanceOf(testAccount1), shares);
    assertGt(shares, 0);
    assertEq(vault.totalAssets(), TEST_DEPOSIT_AMOUNT);
    assertEq(vault.totalSupply(), shares);
  }

  function test_deposit_zeroAmount_reverts() public {
    vm.prank(testAccount1);
    vm.expectRevert(ExternalYieldVault.ZeroAmount.selector);
    vault.deposit(0, testAccount1);
  }

  function test_deposit_differentReceiver() public {
    vm.prank(testAccount1);
    uint256 shares = vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount2);

    assertEq(vault.balanceOf(testAccount1), 0);
    assertEq(vault.balanceOf(testAccount2), shares);
  }

  function test_deposit_multipleUsers() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(testAccount2);
    vault.deposit(TEST_DEPOSIT_AMOUNT * 2, testAccount2);

    vm.prank(testAccount3);
    vault.deposit(TEST_DEPOSIT_AMOUNT / 2, testAccount3);

    assertGt(vault.balanceOf(testAccount1), 0);
    assertGt(
      vault.balanceOf(testAccount2),
      vault.balanceOf(testAccount1)
    );
    assertLt(
      vault.balanceOf(testAccount3),
      vault.balanceOf(testAccount1)
    );
    assertEq(
      vault.totalAssets(),
      TEST_DEPOSIT_AMOUNT +
        TEST_DEPOSIT_AMOUNT *
        2 +
        TEST_DEPOSIT_AMOUNT /
        2
    );
  }

  // ======== MINT TESTS ======== //

  function test_mint_success() public {
    uint256 sharesToMint = vault.previewDeposit(TEST_DEPOSIT_AMOUNT);
    uint256 initialBalance = asset.balanceOf(testAccount1);

    vm.prank(testAccount1);
    uint256 assets = vault.mint(sharesToMint, testAccount1);

    assertLt(asset.balanceOf(testAccount1), initialBalance);
    assertGt(vault.balanceOf(testAccount1), 0);
    assertGt(assets, 0);
  }

  function test_mint_zeroShares_reverts() public {
    vm.prank(testAccount1);
    vm.expectRevert(ExternalYieldVault.ZeroAmount.selector);
    vault.mint(0, testAccount1);
  }

  function test_mint_differentReceiver() public {
    uint256 sharesToMint = vault.previewDeposit(TEST_DEPOSIT_AMOUNT);

    vm.prank(testAccount1);
    vault.mint(sharesToMint, testAccount2);

    assertEq(vault.balanceOf(testAccount1), 0);
    assertGt(vault.balanceOf(testAccount2), 0);
  }

  // ======== WITHDRAW TESTS ======== //

  function test_withdraw_success() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 withdrawAmount = TEST_DEPOSIT_AMOUNT / 2;
    uint256 initialBalance = asset.balanceOf(testAccount1);
    uint256 initialShares = vault.balanceOf(testAccount1);

    vm.prank(testAccount1);
    uint256 shares = vault.withdraw(
      withdrawAmount,
      testAccount1,
      testAccount1
    );

    assertGt(asset.balanceOf(testAccount1), initialBalance);
    assertLt(vault.balanceOf(testAccount1), initialShares);
    assertGt(shares, 0);
  }

  function test_withdraw_zeroAmount_reverts() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(testAccount1);
    vm.expectRevert(ExternalYieldVault.ZeroAmount.selector);
    vault.withdraw(0, testAccount1, testAccount1);
  }

  function test_withdraw_withAllowance() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    vm.prank(testAccount1);
    vault.approve(testAccount2, shares);

    uint256 withdrawAmount = TEST_DEPOSIT_AMOUNT / 2;
    uint256 initialBalance = asset.balanceOf(testAccount3);

    vm.prank(testAccount2);
    vault.withdraw(withdrawAmount, testAccount3, testAccount1);

    assertGt(asset.balanceOf(testAccount3), initialBalance);
  }

  // ======== REDEEM TESTS ======== //

  function test_redeem_success() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialBalance = asset.balanceOf(testAccount1);

    vm.prank(testAccount1);
    uint256 assets = vault.redeem(shares, testAccount1, testAccount1);

    assertEq(vault.balanceOf(testAccount1), 0);
    assertGt(asset.balanceOf(testAccount1), initialBalance);
    assertGt(assets, 0);
  }

  function test_redeem_zeroShares_reverts() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(testAccount1);
    vm.expectRevert(ExternalYieldVault.ZeroAmount.selector);
    vault.redeem(0, testAccount1, testAccount1);
  }

  function test_redeem_partial() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 redeemShares = shares / 4;

    vm.prank(testAccount1);
    vault.redeem(redeemShares, testAccount1, testAccount1);

    assertGt(vault.balanceOf(testAccount1), 0);
    assertEq(vault.balanceOf(testAccount1), shares - redeemShares);
  }

  function test_redeem_withAllowance() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    vm.prank(testAccount1);
    vault.approve(testAccount2, shares);

    uint256 initialBalance = asset.balanceOf(testAccount3);

    vm.prank(testAccount2);
    vault.redeem(shares, testAccount3, testAccount1);

    assertEq(vault.balanceOf(testAccount1), 0);
    assertGt(asset.balanceOf(testAccount3), initialBalance);
  }

  // ======== PREVIEW FUNCTIONS TESTS ======== //

  function test_previewDeposit() public view {
    uint256 expectedShares = vault.previewDeposit(
      TEST_DEPOSIT_AMOUNT
    );
    assertGt(expectedShares, 0);
  }

  function test_previewMint() public view {
    uint256 shares = 1000 * 1e18;
    uint256 expectedAssets = vault.previewMint(shares);
    assertGt(expectedAssets, 0);
  }

  function test_previewWithdraw() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 withdrawAmount = TEST_DEPOSIT_AMOUNT / 2;
    uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
    assertGt(expectedShares, 0);
  }

  function test_previewRedeem() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 expectedAssets = vault.previewRedeem(shares);
    assertGt(expectedAssets, 0);
  }

  // ======== MAX FUNCTIONS TESTS ======== //

  function test_maxDeposit_whenNotPaused() public view {
    assertEq(vault.maxDeposit(testAccount1), type(uint256).max);
  }

  function test_maxDeposit_whenPaused() public {
    vm.prank(globalOwner.owner());
    globalPause.pause();

    assertEq(vault.maxDeposit(testAccount1), 0);
  }

  function test_maxMint_whenNotPaused() public view {
    assertEq(vault.maxMint(testAccount1), type(uint256).max);
  }

  function test_maxMint_whenPaused() public {
    vm.prank(globalOwner.owner());
    globalPause.pause();

    assertEq(vault.maxMint(testAccount1), 0);
  }

  function test_maxWithdraw() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 maxWithdraw = vault.maxWithdraw(testAccount1);
    assertGt(maxWithdraw, 0);
    assertApproxEqRel(maxWithdraw, TEST_DEPOSIT_AMOUNT, 0.01e18);
  }

  function test_maxWithdraw_whenPaused() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(globalOwner.owner());
    globalPause.pause();

    assertEq(vault.maxWithdraw(testAccount1), 0);
  }

  function test_maxRedeem() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    assertEq(vault.maxRedeem(testAccount1), shares);
  }

  function test_maxRedeem_whenPaused() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(globalOwner.owner());
    globalPause.pause();

    assertEq(vault.maxRedeem(testAccount1), 0);
  }

  // ======== YIELD ACCRUAL TESTS ======== //

  function test_yieldAccrual_increasesTotalAssets() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 initialTotalAssets = vault.totalAssets();
    uint256 yieldAmount = TEST_DEPOSIT_AMOUNT / 10; // 10% yield

    krystalVault.simulateYield(yieldAmount);

    uint256 newTotalAssets = vault.totalAssets();
    assertEq(newTotalAssets, initialTotalAssets + yieldAmount);
  }

  function test_yieldAccrual_increasesShareValue() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialRedeemValue = vault.previewRedeem(shares);

    uint256 yieldAmount = TEST_DEPOSIT_AMOUNT / 10; // 10% yield
    krystalVault.simulateYield(yieldAmount);

    uint256 newRedeemValue = vault.previewRedeem(shares);
    assertGt(newRedeemValue, initialRedeemValue);
    assertApproxEqRel(
      newRedeemValue,
      initialRedeemValue + yieldAmount,
      0.01e18
    );
  }

  function test_yieldAccrual_distributedProportionally() public {
    // User 1 deposits 1000
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    // User 2 deposits 2000
    vm.prank(testAccount2);
    vault.deposit(TEST_DEPOSIT_AMOUNT * 2, testAccount2);

    uint256 shares1 = vault.balanceOf(testAccount1);
    uint256 shares2 = vault.balanceOf(testAccount2);

    // Simulate 300 yield (10% of total 3000)
    krystalVault.simulateYield((TEST_DEPOSIT_AMOUNT * 3) / 10);

    uint256 value1 = vault.previewRedeem(shares1);
    uint256 value2 = vault.previewRedeem(shares2);

    // User 2 should have ~2x the value of User 1
    assertApproxEqRel(value2, value1 * 2, 0.01e18);
  }

  // ======== LOSS SIMULATION TESTS ======== //

  function test_loss_decreasesTotalAssets() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 initialTotalAssets = vault.totalAssets();
    uint256 lossAmount = TEST_DEPOSIT_AMOUNT / 10; // 10% loss

    krystalVault.simulateLoss(lossAmount);

    uint256 newTotalAssets = vault.totalAssets();
    assertEq(newTotalAssets, initialTotalAssets - lossAmount);
  }

  function test_loss_decreasesShareValue() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 initialRedeemValue = vault.previewRedeem(shares);

    uint256 lossAmount = TEST_DEPOSIT_AMOUNT / 10; // 10% loss
    krystalVault.simulateLoss(lossAmount);

    uint256 newRedeemValue = vault.previewRedeem(shares);
    assertLt(newRedeemValue, initialRedeemValue);
  }

  // ======== ADMIN FUNCTION TESTS ======== //

  function test_setKrystalVault_success() public {
    MockKrystalVault newKrystalVault = new MockKrystalVault(
      address(asset)
    );

    vm.prank(globalOwner.owner());
    vault.setKrystalVault(address(newKrystalVault));

    assertEq(address(vault.krystalVault()), address(newKrystalVault));
  }

  function test_setKrystalVault_zeroAddress_reverts() public {
    vm.prank(globalOwner.owner());
    vm.expectRevert(ExternalYieldVault.ZeroAddress.selector);
    vault.setKrystalVault(address(0));
  }

  function test_setKrystalVault_onlyOwner() public {
    vm.prank(testAccount1);
    vm.expectRevert();
    vault.setKrystalVault(address(0x123));
  }

  function test_setDefaultSlippageTolerance_success() public {
    uint256 newTolerance = 200; // 2%

    vm.prank(globalOwner.owner());
    vault.setDefaultSlippageTolerance(newTolerance);

    assertEq(vault.slippageToleranceDefault(), newTolerance);
  }

  function test_setDefaultSlippageTolerance_onlyOwner() public {
    vm.prank(testAccount1);
    vm.expectRevert();
    vault.setDefaultSlippageTolerance(200);
  }

  // ======== ACCESS CONTROL TESTS ======== //

  function test_whenPaused_deposit_reverts() public {
    vm.prank(globalOwner.owner());
    globalPause.pause();

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);
  }

  function test_whenPaused_mint_reverts() public {
    vm.prank(globalOwner.owner());
    globalPause.pause();

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.mint(1000 * 1e18, testAccount1);
  }

  function test_whenPaused_withdraw_reverts() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(globalOwner.owner());
    globalPause.pause();

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.withdraw(
      TEST_DEPOSIT_AMOUNT / 2,
      testAccount1,
      testAccount1
    );
  }

  function test_whenPaused_redeem_reverts() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);

    vm.prank(globalOwner.owner());
    globalPause.pause();

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.redeem(shares, testAccount1, testAccount1);
  }

  function test_whenLocalPaused_deposit_reverts() public {
    vm.prank(globalOwner.owner());
    vault.pauseLocal();

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);
  }

  function test_whenLocalUnpaused_deposit_succeeds() public {
    vm.prank(globalOwner.owner());
    vault.pauseLocal();

    vm.prank(globalOwner.owner());
    vault.unpauseLocal();

    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    assertGt(vault.balanceOf(testAccount1), 0);
  }

  function test_restrictedUser_deposit_reverts() public {
    vm.prank(globalOwner.owner());
    globalAccessList.restrictAccount(testAccount1);

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);
  }

  function test_restrictedReceiver_deposit_reverts() public {
    vm.prank(globalOwner.owner());
    globalAccessList.restrictAccount(testAccount2);

    vm.prank(testAccount1);
    vm.expectRevert();
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount2);
  }

  // ======== CONVERSION CONSISTENCY TESTS ======== //

  function test_convertToShares_convertToAssets_consistency() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 testAssets = TEST_DEPOSIT_AMOUNT;
    uint256 shares = vault.convertToShares(testAssets);
    uint256 backToAssets = vault.convertToAssets(shares);

    assertApproxEqRel(testAssets, backToAssets, 0.01e18);
  }

  function test_previewDeposit_matches_actualDeposit() public {
    uint256 expectedShares = vault.previewDeposit(
      TEST_DEPOSIT_AMOUNT
    );

    vm.prank(testAccount1);
    uint256 actualShares = vault.deposit(
      TEST_DEPOSIT_AMOUNT,
      testAccount1
    );

    assertApproxEqRel(expectedShares, actualShares, 0.02e18);
  }

  function test_previewRedeem_matches_actualRedeem() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 expectedAssets = vault.previewRedeem(shares);

    vm.prank(testAccount1);
    uint256 actualAssets = vault.redeem(
      shares,
      testAccount1,
      testAccount1
    );

    assertApproxEqRel(expectedAssets, actualAssets, 0.02e18);
  }

  // ======== EDGE CASE TESTS ======== //

  function test_depositWithZeroTotalSupply() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    assertGt(vault.balanceOf(testAccount1), 0);
    assertEq(vault.totalSupply(), vault.balanceOf(testAccount1));
  }

  function test_fullWithdrawal() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);

    vm.prank(testAccount1);
    vault.redeem(shares, testAccount1, testAccount1);

    assertEq(vault.balanceOf(testAccount1), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.totalAssets(), 0);
  }

  function test_multipleDepositsAndWithdrawals() public {
    // Multiple users deposit
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    vm.prank(testAccount2);
    vault.deposit(TEST_DEPOSIT_AMOUNT * 2, testAccount2);

    vm.prank(testAccount3);
    vault.deposit(TEST_DEPOSIT_AMOUNT / 2, testAccount3);

    // Simulate some yield
    krystalVault.simulateYield(TEST_DEPOSIT_AMOUNT / 10);

    // Partial withdrawals
    uint256 shares1 = vault.balanceOf(testAccount1) / 2;
    vm.prank(testAccount1);
    vault.redeem(shares1, testAccount1, testAccount1);

    // Full withdrawal
    uint256 shares2 = vault.balanceOf(testAccount2);
    vm.prank(testAccount2);
    vault.redeem(shares2, testAccount2, testAccount2);

    // Verify remaining state
    assertGt(vault.balanceOf(testAccount1), 0);
    assertEq(vault.balanceOf(testAccount2), 0);
    assertGt(vault.balanceOf(testAccount3), 0);
    assertGt(vault.totalSupply(), 0);
    assertGt(vault.totalAssets(), 0);
  }

  // ======== SLIPPAGE TESTS ======== //

  function test_slippageTolerance_appliedOnDeposit() public {
    uint256 expectedShares = vault.previewDeposit(
      TEST_DEPOSIT_AMOUNT
    );
    uint256 minShares = (expectedShares *
      (BASIS_POINTS - SLIPPAGE_TOLERANCE)) / BASIS_POINTS;

    vm.prank(testAccount1);
    uint256 actualShares = vault.deposit(
      TEST_DEPOSIT_AMOUNT,
      testAccount1
    );

    assertGe(actualShares, minShares);
  }

  function test_slippageTolerance_appliedOnRedeem() public {
    vm.prank(testAccount1);
    vault.deposit(TEST_DEPOSIT_AMOUNT, testAccount1);

    uint256 shares = vault.balanceOf(testAccount1);
    uint256 expectedAssets = vault.previewRedeem(shares);
    uint256 minAssets = (expectedAssets *
      (BASIS_POINTS - SLIPPAGE_TOLERANCE)) / BASIS_POINTS;

    vm.prank(testAccount1);
    uint256 actualAssets = vault.redeem(
      shares,
      testAccount1,
      testAccount1
    );

    assertGe(actualAssets, minAssets);
  }

  // ======== RECOVER ERC20 TESTS ======== //

  function test_recoverERC20_success() public {
    MockERC20 randomToken = new MockERC20("Random", "RND", 18);
    randomToken.mint(address(vault), 1000 * 1e18);

    uint256 ownerBalanceBefore = randomToken.balanceOf(
      globalOwner.owner()
    );

    vm.prank(globalOwner.owner());
    vault.recoverERC20(address(randomToken), 1000 * 1e18);

    assertEq(
      randomToken.balanceOf(globalOwner.owner()),
      ownerBalanceBefore + 1000 * 1e18
    );
  }

  function test_recoverERC20_onlyOwner() public {
    vm.prank(testAccount1);
    vm.expectRevert();
    vault.recoverERC20(address(asset), 100);
  }
}
