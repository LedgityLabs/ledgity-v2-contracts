// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../foundry/lib/forge-std/src/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LToken } from "../../src/protocol-v1/LToken.sol";
import { LTokenSonic } from "../../src/protocol-v1/sonic/LTokenSonic.sol";
import { LedgityYieldVault } from "../../src/protocol-v2/LedgityYieldVault.sol";

/**
 * @title Skip_LTokenWithdrawalOnlyUpgradeFork
 * @notice Rehearses the live upgrade of the legacy v1 LTokens to the withdrawal-only
 * implementation on a fork of the target chain, then checks that the storage survived
 * and that every exit path (transfer, withdrawal request, migration to the v2 vault)
 * still works while deposits are closed.
 *
 * @dev Skipped by the default suites (Skip_ prefix). Run one chain at a time with
 * `npm run test:upgrade-ltoken:<chain>`, which sets HARDHAT_DEPLOY_FORK and expects
 * <CHAIN>_RPC_URL in the environment.
 *
 * The holder addresses are real accounts holding legacy LTokens at the time of writing
 * (2026-10-29): the owner multisig on Base, the deployer-side wallet on Arbitrum and
 * the liquidity manager on Linea & Sonic. Update them if those balances move.
 */
contract Skip_LTokenWithdrawalOnlyUpgradeFork is Test {
  struct ChainSetup {
    address[] lTokens;
    address[] vaults;
    address holder;
    bool isSonic;
  }

  struct Snapshot {
    string name;
    string symbol;
    uint8 decimals;
    address underlying;
    address globalOwner;
    address globalPause;
    address globalBlacklist;
    address ldyStaking;
    address withdrawer;
    address fund;
    uint32 retentionRateUD7x3;
    uint32 feesRateUD7x3;
    uint16 apr;
    uint256 withdrawalFeeInEth;
    uint256 usableUnderlyings;
    uint256 totalQueued;
    uint256 unclaimedFees;
    uint256 realTotalSupply;
    uint256 totalSupply;
    uint256 withdrawalQueueCursor;
    uint256 holderRealBalance;
    uint256 holderBalance;
  }

  bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  ChainSetup setup_;
  address newImplementation;

  function setUp() public {
    string memory fork = vm.envOr(
      "HARDHAT_DEPLOY_FORK",
      string("base")
    );

    if (_eq(fork, "base")) {
      _fork("BASE");
      setup_.lTokens.push(0x3C769d0e8D21d380228dFB7918c6933bb6ecB6D4); // LUSDC
      setup_.lTokens.push(0x77ce973744745310359B0d1a3415A34FF983708F); // LEURC
      setup_.vaults.push(0x916f179D5D9B7d8Ad815AC2f8570aabF0C6a6e38); // lyUSD
      setup_.vaults.push(0xFaA1e3720e6Ef8cC76A800DB7B3dF8944833b134); // lyEUR
      setup_.holder = 0x972c17D0adA071db4a0395505dD3Ad0a80809053;
    } else if (_eq(fork, "arbitrum")) {
      _fork("ARBITRUM");
      setup_.lTokens.push(0xd54d564606611A3502FE8909bBD3075dbeb77813); // LUSDC
      setup_.vaults.push(0x283F35b6406a0e19a786ed119869eF2c0fE157Ee); // lyUSD
      setup_.holder = 0x4307ea9A2DC3e220d605F93Aa93C6625dbDb8d4e;
    } else if (_eq(fork, "linea")) {
      _fork("LINEA");
      setup_.lTokens.push(0x4AF215DbE27fc030F37f73109B85F421FAB45B7a); // LUSDC
      setup_.vaults.push(0x43b3c64dbc95F9eD83795E051fc00014059e698F); // lyUSD
      setup_.holder = 0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac;
    } else if (_eq(fork, "sonic")) {
      _fork("SONIC");
      setup_.lTokens.push(0xD7cCABfBEfE332C9784FF3debeBdDbc787E75e69); // LUSDC
      setup_.vaults.push(0x65f75c675Cc76474662DfBF7B6e8683764223001); // lyUSD
      setup_.holder = 0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac;
      setup_.isSonic = true;
    } else {
      revert(string.concat("Unsupported fork target: ", fork));
    }

    newImplementation = setup_.isSonic
      ? address(new LTokenSonic())
      : address(new LToken());
    vm.label(newImplementation, "LToken (withdrawal only)");
  }

  // ======== HELPERS ======== //

  /// @dev Same <CHAIN>_RPC_URL / <CHAIN>_FORKING_BLOCK convention as the v2 fixtures;
  ///      pin the block so the tests share one cached fork state instead of hammering the RPC
  function _fork(string memory prefix) internal {
    string memory rpcUrl = vm.envString(
      string.concat(prefix, "_RPC_URL")
    );
    string memory blockStr = vm.envOr(
      string.concat(prefix, "_FORKING_BLOCK"),
      string("")
    );
    if (bytes(blockStr).length > 0 && !_eq(blockStr, "latest")) {
      vm.createSelectFork(rpcUrl, vm.parseUint(blockStr));
    } else {
      vm.createSelectFork(rpcUrl);
    }
  }

  function _eq(
    string memory a,
    string memory b
  ) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }

  function _snapshot(
    LToken lToken
  ) internal view returns (Snapshot memory s) {
    s.name = lToken.name();
    s.symbol = lToken.symbol();
    s.decimals = lToken.decimals();
    s.underlying = address(lToken.underlying());
    s.globalOwner = address(lToken.globalOwner());
    s.globalPause = address(lToken.globalPause());
    s.globalBlacklist = address(lToken.globalBlacklist());
    s.ldyStaking = address(lToken.ldyStaking());
    s.withdrawer = lToken.withdrawer();
    s.fund = lToken.fund();
    s.retentionRateUD7x3 = lToken.retentionRateUD7x3();
    s.feesRateUD7x3 = lToken.feesRateUD7x3();
    s.apr = lToken.getAPR();
    s.withdrawalFeeInEth = lToken.withdrawalFeeInEth();
    s.usableUnderlyings = lToken.usableUnderlyings();
    s.totalQueued = lToken.totalQueued();
    s.unclaimedFees = lToken.unclaimedFees();
    s.realTotalSupply = lToken.realTotalSupply();
    s.totalSupply = lToken.totalSupply();
    s.withdrawalQueueCursor = lToken.withdrawalQueueCursor();
    s.holderRealBalance = lToken.realBalanceOf(setup_.holder);
    s.holderBalance = lToken.balanceOf(setup_.holder);
  }

  function _assertSame(
    Snapshot memory a,
    Snapshot memory b
  ) internal pure {
    assertEq(a.name, b.name, "name");
    assertEq(a.symbol, b.symbol, "symbol");
    assertEq(a.decimals, b.decimals, "decimals");
    assertEq(a.underlying, b.underlying, "underlying");
    assertEq(a.globalOwner, b.globalOwner, "globalOwner");
    assertEq(a.globalPause, b.globalPause, "globalPause");
    assertEq(a.globalBlacklist, b.globalBlacklist, "globalBlacklist");
    assertEq(a.ldyStaking, b.ldyStaking, "ldyStaking");
    assertEq(a.withdrawer, b.withdrawer, "withdrawer");
    assertEq(a.fund, b.fund, "fund");
    assertEq(
      a.retentionRateUD7x3,
      b.retentionRateUD7x3,
      "retentionRateUD7x3"
    );
    assertEq(a.feesRateUD7x3, b.feesRateUD7x3, "feesRateUD7x3");
    assertEq(a.apr, b.apr, "apr");
    assertEq(
      a.withdrawalFeeInEth,
      b.withdrawalFeeInEth,
      "withdrawalFeeInEth"
    );
    assertEq(
      a.usableUnderlyings,
      b.usableUnderlyings,
      "usableUnderlyings"
    );
    assertEq(a.totalQueued, b.totalQueued, "totalQueued");
    assertEq(a.unclaimedFees, b.unclaimedFees, "unclaimedFees");
    assertEq(a.realTotalSupply, b.realTotalSupply, "realTotalSupply");
    assertEq(a.totalSupply, b.totalSupply, "totalSupply");
    assertEq(
      a.withdrawalQueueCursor,
      b.withdrawalQueueCursor,
      "withdrawalQueueCursor"
    );
    assertEq(
      a.holderRealBalance,
      b.holderRealBalance,
      "holderRealBalance"
    );
    assertEq(a.holderBalance, b.holderBalance, "holderBalance");
  }

  /// @dev The two Safe transactions of the rollout: upgradeTo() then switchWithdrawalOnly(true)
  function _upgradeAndClose(LToken lToken) internal {
    address owner = lToken.owner();
    vm.startPrank(owner);
    UUPSUpgradeable(address(lToken)).upgradeTo(newImplementation);
    lToken.switchWithdrawalOnly(true);
    vm.stopPrank();
  }

  // ======== TESTS ======== //

  function test_upgrade_onlyOwner() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      vm.expectRevert(bytes("Ownable: caller is not the owner"));
      vm.prank(address(0xBAD));
      UUPSUpgradeable(setup_.lTokens[i]).upgradeTo(newImplementation);
    }
  }

  function test_upgrade_preservesState() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      Snapshot memory before = _snapshot(lToken);

      vm.prank(lToken.owner());
      UUPSUpgradeable(address(lToken)).upgradeTo(newImplementation);

      assertEq(
        address(
          uint160(
            uint256(vm.load(address(lToken), IMPLEMENTATION_SLOT))
          )
        ),
        newImplementation,
        "implementation slot"
      );
      _assertSame(before, _snapshot(lToken));

      // The appended slots start empty whatever the previous implementation had
      assertEq(lToken.onlyHighTierInstantWithdrawal(), false);
      assertEq(lToken.withdrawalOnly(), false);
    }
  }

  function test_switchWithdrawalOnly_onlyOwner() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      vm.prank(lToken.owner());
      UUPSUpgradeable(address(lToken)).upgradeTo(newImplementation);

      vm.expectRevert(bytes("Ownable: caller is not the owner"));
      vm.prank(address(0xBAD));
      lToken.switchWithdrawalOnly(true);
    }
  }

  function test_withdrawalOnly_blocksDeposit() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      _upgradeAndClose(lToken);
      assertEq(lToken.withdrawalOnly(), true);

      vm.expectRevert(LToken.WithdrawalOnlyMode.selector);
      vm.prank(makeAddr("depositor"));
      lToken.deposit(1, "");
    }
  }

  function test_withdrawalOnly_keepsTransfer() public {
    address recipient = address(0xB0B);
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      _upgradeAndClose(lToken);

      uint256 holderBefore = lToken.realBalanceOf(setup_.holder);
      assertGt(holderBefore, 0, "holder must own legacy LTokens");

      vm.prank(setup_.holder);
      lToken.transfer(recipient, 1);

      assertEq(lToken.realBalanceOf(recipient), 1);
      // Rewards may be minted to the holder on transfer, hence >= and not ==
      assertGe(lToken.realBalanceOf(setup_.holder), holderBefore - 1);
    }
  }

  function test_withdrawalOnly_keepsWithdrawalRequest() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      _upgradeAndClose(lToken);

      uint256 queuedBefore = lToken.totalQueued();
      uint256 fee = lToken.withdrawalFeeInEth();
      vm.deal(setup_.holder, fee);

      vm.prank(setup_.holder);
      lToken.requestWithdrawal{ value: fee }(1);

      assertEq(lToken.totalQueued(), queuedBefore + 1);
    }
  }

  function test_withdrawalOnly_keepsMigrationToVault() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      LedgityYieldVault vault = LedgityYieldVault(setup_.vaults[i]);
      assertEq(
        address(vault.lToken()),
        address(lToken),
        "vault lToken"
      );
      _upgradeAndClose(lToken);

      uint256 amount = lToken.realBalanceOf(setup_.holder);
      assertGt(amount, 0, "holder must own legacy LTokens");
      uint256 sharesBefore = vault.balanceOf(setup_.holder);

      vm.startPrank(setup_.holder);
      lToken.approve(address(vault), amount);
      uint256 shares = vault.migrateLToken(amount);
      vm.stopPrank();

      assertGt(shares, 0, "shares minted");
      assertEq(vault.balanceOf(setup_.holder), sharesBefore + shares);
    }
  }

  function test_switchBack_reopensDeposit() public {
    for (uint256 i; i < setup_.lTokens.length; i++) {
      LToken lToken = LToken(setup_.lTokens[i]);
      _upgradeAndClose(lToken);

      vm.prank(lToken.owner());
      lToken.switchWithdrawalOnly(false);

      // The gate is passed: the next check (underlying balance) is the one that reverts
      vm.expectRevert(LToken.InsufficientBalance.selector);
      vm.prank(makeAddr("depositor"));
      lToken.deposit(1, "");
    }
  }
}
