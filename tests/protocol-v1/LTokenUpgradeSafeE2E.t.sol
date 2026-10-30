// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../foundry/lib/forge-std/src/Test.sol";

import { IERC1822ProxiableUpgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol";

import { LToken } from "../../src/protocol-v1/LToken.sol";

/**
 * @title Skip_LTokenUpgradeSafeE2E
 * @notice Checks a legacy LToken withdrawal-only bundle executed through the real Safe on a
 * local anvil fork by `ledgity-api/scripts/rehearseMultisigBundle.ts`, comparing the block
 * just before the execution with the block just after it: same getter values and same
 * storage slots read, the bundle's implementation, deposits closed, transfers open, no
 * re-initialization.
 *
 * @dev Env: ANVIL_URL, PRE_BLOCK, POST_BLOCK, LTOKENS (comma separated), NEW_IMPL.
 */
contract Skip_LTokenUpgradeSafeE2E is Test {
  bytes32 constant IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  uint256 preFork;
  uint256 postFork;
  address[] lTokens;
  address newImpl;
  // Wallets holding legacy LTokens on some chain (zero balances elsewhere are fine)
  address[] holders = [
    0x972c17D0adA071db4a0395505dD3Ad0a80809053,
    0xE7616e98d2506E571E8f6E38e7Bfd0b55642ACac,
    0xF25a516CAF56895032b3f3eE842b45462Ff491c3,
    0x4307ea9A2DC3e220d605F93Aa93C6625dbDb8d4e,
    0x117B4B046ad3B7f152A688dc9E5461c53B512dAC
  ];

  function setUp() public {
    string memory url = vm.envString("ANVIL_URL");
    preFork = vm.createFork(url, vm.envUint("PRE_BLOCK"));
    postFork = vm.createFork(url, vm.envUint("POST_BLOCK"));
    lTokens = vm.envAddress("LTOKENS", ",");
    newImpl = vm.envAddress("NEW_IMPL");
  }

  function _calls(
    LToken t
  ) internal view returns (bytes[] memory calls) {
    calls = new bytes[](21 + holders.length);
    uint256 n;
    calls[n++] = abi.encodeCall(t.name, ());
    calls[n++] = abi.encodeCall(t.symbol, ());
    calls[n++] = abi.encodeCall(t.decimals, ());
    calls[n++] = abi.encodeCall(t.underlying, ());
    calls[n++] = abi.encodeCall(t.globalOwner, ());
    calls[n++] = abi.encodeCall(t.globalPause, ());
    calls[n++] = abi.encodeCall(t.globalBlacklist, ());
    calls[n++] = abi.encodeCall(t.ldyStaking, ());
    calls[n++] = abi.encodeCall(t.withdrawer, ());
    calls[n++] = abi.encodeCall(t.fund, ());
    calls[n++] = abi.encodeCall(t.retentionRateUD7x3, ());
    calls[n++] = abi.encodeCall(t.feesRateUD7x3, ());
    calls[n++] = abi.encodeCall(t.getAPR, ());
    calls[n++] = abi.encodeCall(t.withdrawalFeeInEth, ());
    calls[n++] = abi.encodeCall(t.usableUnderlyings, ());
    calls[n++] = abi.encodeCall(t.totalQueued, ());
    calls[n++] = abi.encodeCall(t.unclaimedFees, ());
    calls[n++] = abi.encodeCall(t.realTotalSupply, ());
    calls[n++] = abi.encodeCall(t.withdrawalQueueCursor, ());
    calls[n++] = abi.encodeCall(t.paused, ());
    calls[n++] = abi.encodeCall(t.owner, ());
    for (uint256 i; i < holders.length; i++)
      calls[n++] = abi.encodeCall(t.realBalanceOf, (holders[i]));
  }

  function _probe(
    address target,
    bytes memory call
  ) internal returns (bytes memory ret, bytes32[] memory reads) {
    vm.record();
    bool ok;
    (ok, ret) = target.staticcall(call);
    require(ok, "probe reverted");
    (reads, ) = vm.accesses(target);
  }

  function test_e2e_sameValuesAndSlots() public {
    for (uint256 k; k < lTokens.length; k++) {
      LToken t = LToken(lTokens[k]);
      vm.selectFork(preFork);
      bytes[] memory calls = _calls(t);
      bytes[] memory values = new bytes[](calls.length);
      bytes32[][] memory slots = new bytes32[][](calls.length);
      for (uint256 i; i < calls.length; i++)
        (values[i], slots[i]) = _probe(address(t), calls[i]);

      vm.selectFork(postFork);
      for (uint256 i; i < calls.length; i++) {
        (bytes memory value, bytes32[] memory read) = _probe(
          address(t),
          calls[i]
        );
        assertEq(
          value,
          values[i],
          string.concat("value changed, call ", vm.toString(i))
        );
        assertEq(
          read.length,
          slots[i].length,
          string.concat("slots read changed, call ", vm.toString(i))
        );
        for (uint256 j; j < read.length; j++)
          assertEq(
            read[j],
            slots[i][j],
            string.concat("slot read changed, call ", vm.toString(i))
          );
      }
    }
  }

  function test_e2e_upgradedAndClosed() public {
    vm.selectFork(postFork);
    assertEq(
      IERC1822ProxiableUpgradeable(newImpl).proxiableUUID(),
      IMPLEMENTATION_SLOT
    );
    for (uint256 k; k < lTokens.length; k++) {
      LToken t = LToken(lTokens[k]);
      assertEq(
        address(
          uint160(uint256(vm.load(address(t), IMPLEMENTATION_SLOT)))
        ),
        newImpl,
        "implementation"
      );
      assertTrue(t.withdrawalOnly(), "deposits still open");

      // Deposits refused for anyone
      vm.expectRevert(LToken.WithdrawalOnlyMode.selector);
      vm.prank(makeAddr("depositor"));
      t.deposit(1, "");

      // Nobody but the owner can switch, nobody can re-initialize
      vm.expectRevert(bytes("Ownable: caller is not the owner"));
      vm.prank(address(0xBAD));
      t.switchWithdrawalOnly(false);
      vm.expectRevert(
        bytes("Initializable: contract is already initialized")
      );
      t.initialize(
        address(1),
        address(1),
        address(1),
        address(1),
        address(1),
        "x",
        "x"
      );

      // A holder can still move its LTokens
      for (uint256 i; i < holders.length; i++) {
        if (t.realBalanceOf(holders[i]) == 0) continue;
        address recipient = makeAddr("recipient");
        uint256 before = t.realBalanceOf(recipient);
        vm.prank(holders[i]);
        t.transfer(recipient, 1);
        assertEq(t.realBalanceOf(recipient), before + 1, "transfer");
        break;
      }
    }
    vm.expectRevert(
      bytes("Initializable: contract is already initialized")
    );
    LToken(newImpl).initialize(
      address(1),
      address(1),
      address(1),
      address(1),
      address(1),
      "x",
      "x"
    );
  }
}
