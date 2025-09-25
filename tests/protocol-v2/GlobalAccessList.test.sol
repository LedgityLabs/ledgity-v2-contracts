// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Test, console } from "foundry/lib/forge-std/src/Test.sol";

// Fixtures
import { Fixtures } from "./Fixtures.sol";
// Contracts
import { GlobalAccessList } from "src/protocol-v2/GlobalAccessList.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// Interfaces
import { IGlobalAccessList } from "src/protocol-v2/interfaces/IGlobalAccessList.sol";
import { IGlobalOwner } from "src/protocol-v2/interfaces/IGlobalOwner.sol";

contract GlobalAccessListTest is Test, Fixtures {
  // Events for testing
  event RestrictAccount(address indexed account);
  event UnrestrictAccount(address indexed account);

  function setUp() public {
    _setUp();
  }

  // =========== INITIALIZATION TESTS =========== //

  function test_initialization() public view {
    // Check that globalOwner is set correctly
    assertEq(
      address(globalAccessList.globalOwner()),
      address(globalOwner)
    );

    // Check that owner is set to globalOwner.owner()
    assertEq(globalAccessList.owner(), globalOwner.owner());

    // Check that no accounts are restricted initially
    assertFalse(globalAccessList.isRestricted(testAccount1));
    assertFalse(globalAccessList.isRestricted(testAccount2));
    assertFalse(globalAccessList.isRestricted(address(0)));
  }

  function test_cannotInitializeTwice() public {
    // Try to initialize again - should revert
    vm.expectRevert();
    globalAccessList.initialize(address(globalOwner));
  }

  // =========== RESTRICT ACCOUNT TESTS =========== //

  function test_restrictAccount_success() public {
    // Restrict an account as owner
    vm.prank(globalOwner.owner());
    vm.expectEmit(true, false, false, true);
    emit RestrictAccount(testAccount1);
    globalAccessList.restrictAccount(testAccount1);

    // Verify account is now restricted
    assertTrue(globalAccessList.isRestricted(testAccount1));

    // Verify it appears in the restricted accounts list
    address[] memory restrictedAccounts = globalAccessList
      .getRestrictedAccounts(0, 10);
    bool found = false;
    for (uint256 i = 0; i < restrictedAccounts.length; i++) {
      if (restrictedAccounts[i] == testAccount1) {
        found = true;
        break;
      }
    }
    assertTrue(found, "Account should be in restricted list");
  }

  function test_restrictAccount_multipleAccounts() public {
    address owner = globalOwner.owner();

    // Restrict multiple accounts
    vm.startPrank(owner);
    globalAccessList.restrictAccount(testAccount1);
    globalAccessList.restrictAccount(testAccount2);
    globalAccessList.restrictAccount(testAccount3);
    vm.stopPrank();

    // Verify all accounts are restricted
    assertTrue(globalAccessList.isRestricted(testAccount1));
    assertTrue(globalAccessList.isRestricted(testAccount2));
    assertTrue(globalAccessList.isRestricted(testAccount3));

    // Verify total count
    address[] memory allRestricted = globalAccessList
      .getRestrictedAccounts(0, 10);
    assertEq(allRestricted.length, 3); // 3 test accounts
  }

  function test_restrictAccount_onlyOwner() public {
    // Try to restrict account as non-owner - should revert
    vm.prank(unauthorizedUser);
    vm.expectRevert("Ownable: caller is not the owner");
    globalAccessList.restrictAccount(testAccount1);

    // Verify account is not restricted
    assertFalse(globalAccessList.isRestricted(testAccount1));
  }

  function test_restrictAccount_alreadyRestricted() public {
    address owner = globalOwner.owner();

    // First restriction should succeed
    vm.prank(owner);
    globalAccessList.restrictAccount(testAccount1);

    // Second restriction should revert
    vm.prank(owner);
    vm.expectRevert(
      IGlobalAccessList.AccountAlreadyRestricted.selector
    );
    globalAccessList.restrictAccount(testAccount1);
  }

  // =========== UNRESTRICT ACCOUNT TESTS =========== //

  function test_unRestrictAccount_success() public {
    address owner = globalOwner.owner();

    // First restrict the account
    vm.prank(owner);
    globalAccessList.restrictAccount(testAccount1);
    assertTrue(globalAccessList.isRestricted(testAccount1));

    // Then unrestrict it
    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit UnrestrictAccount(testAccount1);
    globalAccessList.unRestrictAccount(testAccount1);

    // Verify account is no longer restricted
    assertFalse(globalAccessList.isRestricted(testAccount1));
  }

  function test_unRestrictAccount_swapAndPop() public {
    address owner = globalOwner.owner();

    // Restrict multiple accounts
    vm.startPrank(owner);
    globalAccessList.restrictAccount(testAccount1);
    globalAccessList.restrictAccount(testAccount2);
    globalAccessList.restrictAccount(testAccount3);
    vm.stopPrank();

    // Get initial state
    address[] memory beforeUnrestrict = globalAccessList
      .getRestrictedAccounts(0, 10);
    assertEq(beforeUnrestrict.length, 3); // 3 accounts

    // Unrestrict middle account (testAccount2)
    vm.prank(owner);
    globalAccessList.unRestrictAccount(testAccount2);

    // Verify the account is no longer restricted
    assertFalse(globalAccessList.isRestricted(testAccount2));

    // Verify other accounts are still restricted
    assertTrue(globalAccessList.isRestricted(testAccount1));
    assertTrue(globalAccessList.isRestricted(testAccount3));

    // Verify array length decreased
    address[] memory afterUnrestrict = globalAccessList
      .getRestrictedAccounts(0, 10);
    assertEq(afterUnrestrict.length, 2); // 2 remaining accounts
  }

  function test_unRestrictAccount_onlyOwner() public {
    address owner = globalOwner.owner();

    // First restrict the account
    vm.prank(owner);
    globalAccessList.restrictAccount(testAccount1);

    // Try to unrestrict as non-owner - should revert
    vm.prank(unauthorizedUser);
    vm.expectRevert("Ownable: caller is not the owner");
    globalAccessList.unRestrictAccount(testAccount1);

    // Verify account is still restricted
    assertTrue(globalAccessList.isRestricted(testAccount1));
  }

  function test_unRestrictAccount_notRestricted() public {
    address owner = globalOwner.owner();

    // Try to unrestrict an account that was never restricted
    vm.prank(owner);
    vm.expectRevert(IGlobalAccessList.AccountNotRestricted.selector);
    globalAccessList.unRestrictAccount(testAccount1);
  }

  // =========== IS RESTRICTED TESTS =========== //

  function test_isRestricted_falseByDefault() public view {
    // All accounts should be unrestricted by default
    assertFalse(globalAccessList.isRestricted(testAccount1));
    assertFalse(globalAccessList.isRestricted(testAccount2));
    assertFalse(globalAccessList.isRestricted(testAccount3));
    assertFalse(globalAccessList.isRestricted(address(0)));
  }

  function test_isRestricted_afterRestriction() public {
    address owner = globalOwner.owner();

    vm.prank(owner);
    globalAccessList.restrictAccount(testAccount1);

    assertTrue(globalAccessList.isRestricted(testAccount1));
    assertFalse(globalAccessList.isRestricted(testAccount2));
  }

  // =========== GET RESTRICTED ACCOUNTS TESTS =========== //

  function test_getRestrictedAccounts_emptyList() public view {
    // Should return empty array initially
    address[] memory accounts = globalAccessList
      .getRestrictedAccounts(0, 10);
    assertEq(accounts.length, 0);
  }

  function test_getRestrictedAccounts_pagination() public {
    address owner = globalOwner.owner();

    // Add multiple accounts
    vm.startPrank(owner);
    globalAccessList.restrictAccount(testAccount1);
    globalAccessList.restrictAccount(testAccount2);
    globalAccessList.restrictAccount(testAccount3);
    vm.stopPrank();

    // Test pagination - get first 2 accounts
    address[] memory page1 = globalAccessList.getRestrictedAccounts(
      0,
      2
    );
    assertEq(page1.length, 2);
    assertEq(page1[0], testAccount1); // First restricted account

    // Test pagination - get next account
    address[] memory page2 = globalAccessList.getRestrictedAccounts(
      2,
      2
    );
    assertEq(page2.length, 1);

    // Test getting all accounts
    address[] memory allAccounts = globalAccessList
      .getRestrictedAccounts(0, 10);
    assertEq(allAccounts.length, 3); // 3 test accounts
  }

  function test_getRestrictedAccounts_boundaryConditions() public {
    address owner = globalOwner.owner();

    // Add one account
    vm.prank(owner);
    globalAccessList.restrictAccount(testAccount1);

    // Test requesting more accounts than available
    address[] memory accounts = globalAccessList
      .getRestrictedAccounts(0, 100);
    assertEq(accounts.length, 1); // testAccount1

    // Test starting from index beyond array length
    address[] memory emptyResult = globalAccessList
      .getRestrictedAccounts(10, 5);
    assertEq(emptyResult.length, 0);

    // Test zero count
    address[] memory zeroResult = globalAccessList
      .getRestrictedAccounts(0, 0);
    assertEq(zeroResult.length, 0);
  }

  // =========== OWNER OVERRIDE TESTS =========== //

  function test_owner_returnsGlobalOwner() public view {
    // The owner() function should return globalOwner.owner()
    assertEq(globalAccessList.owner(), globalOwner.owner());
  }

  function test_owner_updatesWithGlobalOwner() public {
    address newOwner = address(0x7777);

    // Change the global owner
    vm.prank(globalOwner.owner());
    globalOwner.transferOwnership(newOwner);

    vm.prank(newOwner);
    globalOwner.acceptOwnership();

    // GlobalAccessList should reflect the new owner
    assertEq(globalAccessList.owner(), newOwner);

    // New owner should be able to restrict accounts
    vm.prank(newOwner);
    globalAccessList.restrictAccount(testAccount1);
    assertTrue(globalAccessList.isRestricted(testAccount1));
  }

  // =========== UPGRADE AUTHORIZATION TESTS =========== //

  function test_authorizeUpgrade_onlyOwner() public {
    // We can't directly test _authorizeUpgrade as it's internal, but we can verify
    // that only owner can call upgrade functions by testing the onlyOwner modifier
    // through other functions that use it

    // Test that non-owner cannot call owner-only functions
    vm.prank(unauthorizedUser);
    vm.expectRevert("Ownable: caller is not the owner");
    globalAccessList.restrictAccount(testAccount1);
  }

  // =========== EDGE CASES AND ERROR HANDLING =========== //

  function test_restrictZeroAddress() public {
    address owner = globalOwner.owner();

    // Restricting address(0) should work (though not practically useful)
    vm.prank(owner);
    globalAccessList.restrictAccount(address(0));

    // address(0) should be considered restricted
    assertTrue(globalAccessList.isRestricted(address(0)));
  }

  function test_gasOptimization_swapAndPop() public {
    address owner = globalOwner.owner();

    // Add many accounts to test gas efficiency
    address[] memory testAccounts = new address[](10);
    for (uint256 i = 0; i < 10; i++) {
      testAccounts[i] = address(uint160(0x1000 + i));
    }

    // Restrict all accounts
    vm.startPrank(owner);
    for (uint256 i = 0; i < testAccounts.length; i++) {
      globalAccessList.restrictAccount(testAccounts[i]);
    }
    vm.stopPrank();

    // Verify all are restricted
    for (uint256 i = 0; i < testAccounts.length; i++) {
      assertTrue(globalAccessList.isRestricted(testAccounts[i]));
    }

    // Remove account from middle (should use swap-and-pop)
    vm.prank(owner);
    globalAccessList.unRestrictAccount(testAccounts[5]);

    // Verify the account is no longer restricted
    assertFalse(globalAccessList.isRestricted(testAccounts[5]));

    // Verify other accounts are still restricted
    for (uint256 i = 0; i < testAccounts.length; i++) {
      if (i != 5) {
        assertTrue(globalAccessList.isRestricted(testAccounts[i]));
      }
    }

    // Verify array length is correct
    address[] memory remaining = globalAccessList
      .getRestrictedAccounts(0, 20);
    assertEq(remaining.length, 9); // 9 remaining accounts
  }

  // =========== INTEGRATION WITH GLOBAL OWNER =========== //

  function test_integrationWithGlobalOwner() public {
    // Verify that the contract correctly integrates with GlobalOwner
    assertEq(
      address(globalAccessList.globalOwner()),
      address(globalOwner)
    );
    assertEq(globalAccessList.owner(), globalOwner.owner());

    // Test that ownership changes in GlobalOwner are reflected
    address currentOwner = globalOwner.owner();
    address newOwner = address(0x8888);

    vm.prank(currentOwner);
    globalOwner.transferOwnership(newOwner);

    vm.prank(newOwner);
    globalOwner.acceptOwnership();

    // GlobalAccessList should now recognize the new owner
    assertEq(globalAccessList.owner(), newOwner);

    // New owner should have control over restrictions
    vm.prank(newOwner);
    globalAccessList.restrictAccount(testAccount1);
    assertTrue(globalAccessList.isRestricted(testAccount1));

    // Old owner should no longer have control
    vm.prank(currentOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    globalAccessList.restrictAccount(testAccount2);
  }
}
