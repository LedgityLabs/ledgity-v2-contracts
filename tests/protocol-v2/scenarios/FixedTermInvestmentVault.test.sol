// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

// Foundry
import { Test, console } from "foundry/lib/forge-std/src/Test.sol";
// Contracts
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { FixedTermInvestmentVault } from "src/protocol-v2/FixedTermInvestmentVault.sol";
import { LedgityYieldVault } from "src/protocol-v2/LedgityYieldVault.sol";
import { GlobalOwner } from "src/protocol-v1/GlobalOwner.sol";
import { GlobalPause } from "src/protocol-v1/GlobalPause.sol";
import { GlobalAccessList } from "src/protocol-v2/GlobalAccessList.sol";
// Interfaces
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILedgityDataProvider } from "src/protocol-v2/interfaces/ILedgityDataProvider.sol";
import { ILedgityYieldVault } from "src/protocol-v2/interfaces/ILedgityYieldVault.sol";
import { IVaultLiquidityModule } from "src/protocol-v2/interfaces/IVaultLiquidityModule.sol";
import { IAaveLendingPoolV3 } from "src/protocol-v2/interfaces/IAaveLendingPoolV3.sol";

contract FixedTermMockERC20 is ERC20 {
  uint8 private immutable _decimals;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20(name_, symbol_) {
    _decimals = decimals_;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }
}

contract FixedTermInvestmentVault_Test is Test {
  uint256 private constant RAY = 1e27;
  uint256 private constant INITIAL_BALANCE = 1_000_000 ether;
  uint256 private constant CAPACITY = 1_000 ether;
  uint256 private constant ONE_WEEK = 7 days;
  uint256 private constant THIRTY_DAYS = 30 days;

  address private alice = address(0xA11CE);
  address private bob = address(0xB0B);
  address private carol = address(0xCA401);
  address private operator = address(0x0A11);
  address private liquidityManager = address(0x777);
  address payable private feeRecipient = payable(address(0xfee));

  FixedTermMockERC20 private asset;
  GlobalOwner private globalOwner;
  GlobalPause private globalPause;
  GlobalAccessList private globalAccessList;
  FixedTermInvestmentVault private vault;

  function setUp() public {
    asset = new FixedTermMockERC20("Mock USD", "mUSD", 18);
    asset.mint(alice, INITIAL_BALANCE);
    asset.mint(bob, INITIAL_BALANCE);
    asset.mint(carol, INITIAL_BALANCE);
    asset.mint(liquidityManager, INITIAL_BALANCE);

    globalOwner = GlobalOwner(
      address(
        new ERC1967Proxy(
          address(new GlobalOwner()),
          abi.encodeWithSelector(GlobalOwner.initialize.selector)
        )
      )
    );
    globalPause = GlobalPause(
      address(
        new ERC1967Proxy(
          address(new GlobalPause()),
          abi.encodeWithSelector(
            GlobalPause.initialize.selector,
            address(globalOwner)
          )
        )
      )
    );
    globalAccessList = GlobalAccessList(
      address(
        new ERC1967Proxy(
          address(new GlobalAccessList()),
          abi.encodeWithSelector(
            GlobalAccessList.initialize.selector,
            address(globalOwner)
          )
        )
      )
    );

    vault = _createVault(CAPACITY, block.timestamp + THIRTY_DAYS);

    _approveVault(alice);
    _approveVault(bob);
    _approveVault(carol);
    _approveVault(liquidityManager);
  }

  function test_initializesFixedTermInvestmentParams() public view {
    assertEq(vault.maxDepositCapacity(), CAPACITY);
    assertEq(vault.operationEndDate(), block.timestamp + THIRTY_DAYS);
    assertTrue(vault.withdrawalRequestsEnabled());
    assertEq(address(vault.asset()), address(asset));
    assertEq(vault.owner(), address(this));
    assertEq(vault.name(), "Fixed Term Vault");
    assertEq(vault.symbol(), "ftUSD");
  }

  function test_depositAllowsExactCapacityAndRejectsOneWeiMore()
    public
  {
    vm.prank(alice);
    vault.deposit(CAPACITY, alice);

    assertEq(vault.totalAssets(), CAPACITY);

    vm.prank(bob);
    vm.expectRevert(
      FixedTermInvestmentVault.DepositCapacityExceeded.selector
    );
    vault.deposit(1, bob);
  }

  function test_zeroCapacityDisablesDepositCap() public {
    vault.updateMaxDepositCapacity(0);

    vm.prank(alice);
    vault.deposit(CAPACITY, alice);

    vm.prank(bob);
    vault.deposit(CAPACITY, bob);

    assertEq(vault.maxDepositCapacity(), 0);
    assertEq(vault.totalAssets(), CAPACITY * 2);
  }

  function test_depositUsesTotalAssetsAcrossMultipleUsers() public {
    vm.prank(alice);
    vault.deposit(400 ether, alice);

    vm.prank(bob);
    vault.deposit(350 ether, bob);

    vm.prank(carol);
    vault.deposit(250 ether, carol);

    assertEq(vault.totalAssets(), CAPACITY);
    assertGt(vault.balanceOf(alice), vault.balanceOf(carol));
    assertGt(vault.balanceOf(bob), vault.balanceOf(carol));
  }

  function test_depositForDifferentReceiverCountsTowardCapacity()
    public
  {
    vm.prank(alice);
    vault.deposit(999 ether, bob);

    assertEq(vault.balanceOf(alice), 0);
    assertGt(vault.balanceOf(bob), 0);

    vm.prank(carol);
    vm.expectRevert(
      FixedTermInvestmentVault.DepositCapacityExceeded.selector
    );
    vault.deposit(2 ether, carol);
  }

  function test_mintRespectsCapacity() public {
    vm.prank(alice);
    vault.deposit(900 ether, alice);

    uint256 sharesWithinCapacity = vault.convertToShares(100 ether);
    vm.prank(bob);
    vault.mint(sharesWithinCapacity, bob);

    assertEq(vault.totalAssets(), CAPACITY);

    vm.prank(carol);
    vm.expectRevert(
      FixedTermInvestmentVault.DepositCapacityExceeded.selector
    );
    vault.mint(1, carol);
  }

  function test_adminCanIncreaseCapacityAndDepositsContinue() public {
    vm.prank(alice);
    vault.deposit(CAPACITY, alice);

    vm.prank(bob);
    vm.expectRevert(
      FixedTermInvestmentVault.DepositCapacityExceeded.selector
    );
    vault.deposit(1 ether, bob);

    vault.updateMaxDepositCapacity(CAPACITY + 1 ether);

    vm.prank(bob);
    vault.deposit(1 ether, bob);

    assertEq(vault.maxDepositCapacity(), CAPACITY + 1 ether);
    assertGt(vault.balanceOf(bob), 0);
  }

  function test_adminCanLowerCapacityBelowCurrentAssets() public {
    vm.prank(alice);
    vault.deposit(800 ether, alice);

    vault.updateMaxDepositCapacity(500 ether);

    assertEq(vault.maxDepositCapacity(), 500 ether);

    vm.prank(bob);
    vm.expectRevert(
      FixedTermInvestmentVault.DepositCapacityExceeded.selector
    );
    vault.deposit(1, bob);
  }

  function test_adminCanMoveEndDateForwardAndBackward() public {
    uint256 laterEndDate = vault.operationEndDate() + THIRTY_DAYS;

    vault.updateOperationEndDate(laterEndDate);
    assertEq(vault.operationEndDate(), laterEndDate);

    uint256 earlierEndDate = block.timestamp + ONE_WEEK;
    vault.updateOperationEndDate(earlierEndDate);
    assertEq(vault.operationEndDate(), earlierEndDate);
  }

  function test_zeroEndDateDisablesWithdrawalLock() public {
    vault.updateOperationEndDate(0);

    vm.prank(alice);
    vault.deposit(100 ether, alice);

    vm.prank(liquidityManager);
    vault.depositToBuffer(100 ether);

    uint256 initialBalance = asset.balanceOf(alice);

    vm.prank(alice);
    vault.withdraw(10 ether, alice, alice);

    assertEq(vault.operationEndDate(), 0);
    assertEq(asset.balanceOf(alice), initialBalance + 10 ether);
  }

  function test_onlyAdminCanUpdateInvestmentParams() public {
    vm.expectRevert();
    vm.prank(alice);
    vault.updateMaxDepositCapacity(CAPACITY + 1);

    vm.expectRevert();
    vm.prank(bob);
    vault.updateOperationEndDate(block.timestamp + ONE_WEEK);
  }

  function test_onlyAdminCanUpdateWithdrawalRequestSwitch() public {
    vm.expectRevert();
    vm.prank(alice);
    vault.updateWithdrawalRequestsEnabled(false);
  }

  function test_withdrawAndRedeemRevertBeforeOperationEndDate()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vault.withdraw(1 ether, alice, alice);

    vm.prank(alice);
    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vault.redeem(shares, alice, alice);
  }

  function test_approvedOperatorCannotWithdrawBeforeEndDate() public {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.approve(operator, shares);

    vm.prank(operator);
    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vault.redeem(shares, operator, alice);
  }

  function test_zeroEndDateStillAllowsWithdrawalRequests() public {
    vault.updateOperationEndDate(0);

    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(shares);

    assertEq(vault.balanceOf(alice), 0);
    assertEq(vault.getWithdrawalRequestCount(), 1);
  }

  function test_requestWithdrawalWorksBeforeOperationEndDate()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(shares);

    assertEq(vault.balanceOf(alice), 0);
    assertEq(vault.getWithdrawalRequestCount(), 1);

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);

    assertEq(requests[0].user, alice);
    assertEq(requests[0].amount, 100 ether);
    assertFalse(requests[0].processed);

    vm.prank(liquidityManager);
    vault.processRequests(_requestIds(0), requests[0].amount);

    assertTrue(vault.getWithdrawalRequests(false, 0)[0].processed);
  }

  function test_requestWithdrawalWorksAtOperationEndDate() public {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.warp(vault.operationEndDate());

    vm.prank(alice);
    vault.requestWithdrawal(shares);

    assertEq(vault.balanceOf(alice), 0);
    assertEq(vault.getWithdrawalRequestCount(), 1);
  }

  function test_disablingWithdrawalRequestsCancelsPendingAndBlocksNewRequests()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);
    vm.prank(bob);
    vault.deposit(100 ether, bob);

    uint256 aliceShares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(aliceShares);

    assertEq(vault.balanceOf(alice), 0);

    vault.updateWithdrawalRequestsEnabled(false);

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);

    assertFalse(vault.withdrawalRequestsEnabled());
    assertTrue(requests[0].processed);
    assertEq(vault.balanceOf(alice), aliceShares);

    uint256 bobShares = vault.balanceOf(bob);

    vm.expectRevert(
      FixedTermInvestmentVault.WithdrawalRequestsDisabled.selector
    );
    vm.prank(bob);
    vault.requestWithdrawal(bobShares);
  }

  function test_adminCanCancelSelectedPendingWithdrawalRequests()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);
    vm.prank(bob);
    vault.deposit(100 ether, bob);

    uint256 aliceShares = vault.balanceOf(alice);
    uint256 bobShares = vault.balanceOf(bob);

    vm.prank(alice);
    vault.requestWithdrawal(aliceShares);
    vm.prank(bob);
    vault.requestWithdrawal(bobShares);

    vault.cancelPendingWithdrawalRequests(_requestIds(0));

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);

    assertTrue(requests[0].processed);
    assertFalse(requests[1].processed);
    assertEq(vault.balanceOf(alice), aliceShares);
    assertEq(vault.balanceOf(bob), 0);
  }

  function test_cancellingWithdrawalRequestRestoresSharesAtLatestPps()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);
    vm.prank(bob);
    vault.deposit(100 ether, bob);

    uint256 aliceShares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(aliceShares);

    vault.setTotalAssets(110 ether);

    uint256 expectedAssets = vault.convertToAssets(aliceShares);

    vault.cancelPendingWithdrawalRequests(_requestIds(0));

    assertEq(vault.balanceOf(alice), aliceShares);
    assertEq(vault.convertToAssets(aliceShares), expectedAssets);
  }

  function test_adminCanHandleWithdrawalRequestBeforeEndDate()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(shares / 2);

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);

    uint256 initialBalance = asset.balanceOf(alice);

    vm.prank(liquidityManager);
    vault.processRequests(_requestIds(0), requests[0].amount);

    assertTrue(vault.getWithdrawalRequests(false, 0)[0].processed);
    assertEq(
      asset.balanceOf(alice),
      initialBalance + requests[0].amount
    );

    uint256 remainingShares = vault.balanceOf(alice);

    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vm.prank(alice);
    vault.redeem(remainingShares, alice, alice);
  }

  function test_partialRequestWithdrawalLeavesRemainingSharesLocked()
    public
  {
    vm.prank(alice);
    vault.deposit(200 ether, alice);

    uint256 requestedShares = vault.balanceOf(alice) / 2;

    vm.prank(alice);
    vault.requestWithdrawal(requestedShares);

    assertGt(vault.balanceOf(alice), 0);
    assertEq(vault.getWithdrawalRequestCount(), 1);

    uint256 remainingShares = vault.balanceOf(alice);

    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vm.prank(alice);
    vault.redeem(remainingShares, alice, alice);
  }

  function test_multipleRequestsCanBeProcessedTogetherBeforeEndDate()
    public
  {
    vm.prank(alice);
    vault.deposit(200 ether, alice);
    vm.prank(bob);
    vault.deposit(300 ether, bob);

    uint256 aliceShares = vault.balanceOf(alice);
    uint256 bobShares = vault.balanceOf(bob);

    vm.prank(alice);
    vault.requestWithdrawal(aliceShares);
    vm.prank(bob);
    vault.requestWithdrawal(bobShares);

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);
    uint256 liquidityRequired = requests[0].amount +
      requests[1].amount;

    uint256 initialAliceAssets = asset.balanceOf(alice);
    uint256 initialBobAssets = asset.balanceOf(bob);

    vm.prank(liquidityManager);
    vault.processRequests(_requestIds(0, 1), liquidityRequired);

    requests = vault.getWithdrawalRequests(false, 0);

    assertTrue(requests[0].processed);
    assertTrue(requests[1].processed);
    assertEq(asset.balanceOf(alice), initialAliceAssets + 200 ether);
    assertEq(asset.balanceOf(bob), initialBobAssets + 300 ether);
  }

  function test_processRequestsStillRequiresLiquidityManager()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    uint256 shares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.requestWithdrawal(shares);

    vm.prank(alice);
    vm.expectRevert(LedgityYieldVault.OnlyLiquidityManager.selector);
    vault.processRequests(_requestIds(0), 100 ether);
  }

  function test_withdrawSucceedsAtOperationEndDate() public {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    vm.prank(liquidityManager);
    vault.depositToBuffer(100 ether);

    vm.warp(vault.operationEndDate());

    uint256 initialBalance = asset.balanceOf(alice);

    vm.prank(alice);
    vault.withdraw(10 ether, alice, alice);

    assertEq(asset.balanceOf(alice), initialBalance + 10 ether);
  }

  function test_redeemSucceedsAfterOperationEndDate() public {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    vm.prank(liquidityManager);
    vault.depositToBuffer(100 ether);

    vm.warp(vault.operationEndDate() + 1);

    uint256 shares = vault.balanceOf(alice);
    uint256 initialBalance = asset.balanceOf(alice);

    vm.prank(alice);
    vault.redeem(shares, alice, alice);

    assertEq(vault.balanceOf(alice), 0);
    assertEq(asset.balanceOf(alice), initialBalance + 100 ether);
  }

  function test_approvedOperatorCanRedeemAfterOperationEndDate()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    vm.prank(liquidityManager);
    vault.depositToBuffer(100 ether);

    uint256 shares = vault.balanceOf(alice);
    vm.prank(alice);
    vault.approve(operator, shares);

    vm.warp(vault.operationEndDate());

    vm.prank(operator);
    vault.redeem(shares, bob, alice);

    assertEq(vault.balanceOf(alice), 0);
    assertEq(asset.balanceOf(bob), INITIAL_BALANCE + 100 ether);
  }

  function test_pausedVaultStillBlocksDepositsAndWithdrawals()
    public
  {
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    vm.warp(vault.operationEndDate());

    vm.prank(liquidityManager);
    vault.depositToBuffer(100 ether);

    globalPause.pause();

    vm.prank(bob);
    vm.expectRevert();
    vault.deposit(1 ether, bob);

    vm.prank(alice);
    vm.expectRevert();
    vault.withdraw(1 ether, alice, alice);
  }

  function test_restrictedUserCannotDepositOrRequestWithdrawal()
    public
  {
    globalAccessList.restrictAccount(alice);

    vm.expectRevert();
    vm.prank(alice);
    vault.deposit(100 ether, alice);

    globalAccessList.unRestrictAccount(alice);

    vm.prank(alice);
    vault.deposit(100 ether, alice);

    globalAccessList.restrictAccount(alice);

    uint256 shares = vault.balanceOf(alice);

    vm.expectRevert();
    vm.prank(alice);
    vault.requestWithdrawal(shares);
  }

  function test_scenario_capacityEndDateRequestsAndFinalExit()
    public
  {
    vm.prank(alice);
    vault.deposit(500 ether, alice);

    vm.prank(bob);
    vault.deposit(300 ether, bob);

    vm.prank(carol);
    vault.deposit(200 ether, carol);

    assertEq(vault.totalAssets(), CAPACITY);

    vm.prank(alice);
    vm.expectRevert(
      FixedTermInvestmentVault.OperationNotEnded.selector
    );
    vault.withdraw(10 ether, alice, alice);

    vault.updateOperationEndDate(block.timestamp + ONE_WEEK);

    uint256 aliceRequestShares = vault.balanceOf(alice) / 2;
    uint256 carolRequestShares = vault.balanceOf(carol);

    vm.prank(alice);
    vault.requestWithdrawal(aliceRequestShares);

    vm.prank(carol);
    vault.requestWithdrawal(carolRequestShares);

    ILedgityDataProvider.WithdrawalRequestRead[]
      memory requests = vault.getWithdrawalRequests(false, 0);
    uint256 requestLiquidity = requests[0].amount +
      requests[1].amount;

    vm.prank(liquidityManager);
    vault.processRequests(_requestIds(0, 1), requestLiquidity);

    vm.warp(vault.operationEndDate());

    vm.prank(liquidityManager);
    vault.depositToBuffer(600 ether);

    uint256 bobShares = vault.balanceOf(bob);
    uint256 aliceShares = vault.balanceOf(alice);

    vm.prank(alice);
    vault.redeem(aliceShares, alice, alice);

    vm.prank(bob);
    vault.redeem(bobShares, bob, bob);

    requests = vault.getWithdrawalRequests(false, 0);

    assertTrue(requests[0].processed);
    assertTrue(requests[1].processed);
    assertEq(vault.balanceOf(alice), 0);
    assertEq(vault.balanceOf(bob), 0);
    assertEq(vault.balanceOf(carol), 0);
  }

  function _createVault(
    uint256 maxDepositCapacity,
    uint256 operationEndDate
  ) internal returns (FixedTermInvestmentVault) {
    FixedTermInvestmentVault implementation = new FixedTermInvestmentVault();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(implementation),
      ""
    );
    FixedTermInvestmentVault fixedTermVault = FixedTermInvestmentVault(
        address(proxy)
      );

    fixedTermVault.initialize(
      ILedgityYieldVault.VaultParams({
        name: "Fixed Term Vault",
        symbol: "ftUSD",
        asset: IERC20(address(asset)),
        lToken: IERC20(address(0)),
        stakeToken: IERC20(address(0)),
        stakeForFeeReduction: 0,
        stakeForInstantWithdrawal: 0,
        globalOwner: address(globalOwner),
        globalPause: address(globalPause),
        globalAccessList: address(globalAccessList),
        liquidityManager: liquidityManager,
        feeRecipient: feeRecipient,
        liquidityBufferRate: 0,
        aaveLendingPool: IAaveLendingPoolV3(address(0))
      }),
      IVaultLiquidityModule.VaultLiquidityInitParams({
        highWaterMark: 0,
        deploymentDelay: 0,
        initialAssetsPerShare: 0,
        yieldAPR: 0,
        managementFeeRate: 0,
        performanceFeeRate: 0,
        withdrawalFeeRate: 0,
        withdrawalGasFee: 0
      })
    );

    fixedTermVault.updateMaxDepositCapacity(maxDepositCapacity);
    fixedTermVault.updateOperationEndDate(operationEndDate);

    return fixedTermVault;
  }

  function _approveVault(address user) internal {
    vm.prank(user);
    asset.approve(address(vault), type(uint256).max);
  }

  function _requestIds(
    uint256 requestId
  ) internal pure returns (uint256[] memory requestIds) {
    requestIds = new uint256[](1);
    requestIds[0] = requestId;
  }

  function _requestIds(
    uint256 requestId0,
    uint256 requestId1
  ) internal pure returns (uint256[] memory requestIds) {
    requestIds = new uint256[](2);
    requestIds[0] = requestId0;
    requestIds[1] = requestId1;
  }
}
