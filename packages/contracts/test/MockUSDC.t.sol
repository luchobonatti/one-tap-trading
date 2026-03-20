// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MockUSDC } from "src/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC internal usdc;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        // Test contract is msg.sender → becomes the Ownable owner.
        usdc = new MockUSDC();
    }

    // ─── Metadata ────────────────────────────────────────────────────────────

    function test_NameIsCorrect() public view {
        assertEq(usdc.name(), "Mock USD Coin");
    }

    function test_SymbolIsCorrect() public view {
        assertEq(usdc.symbol(), "USDC");
    }

    function test_DecimalsIsSix() public view {
        assertEq(usdc.decimals(), 6);
    }

    function test_FaucetCapIsCorrect() public view {
        assertEq(usdc.FAUCET_AMOUNT(), 10_000e6);
    }

    function test_OwnerIsDeployer() public view {
        assertEq(usdc.owner(), address(this));
    }

    // ─── faucet happy path ───────────────────────────────────────────────────

    function test_FaucetMintsToSender() public {
        vm.prank(alice);
        usdc.faucet(1000e6);
        assertEq(usdc.balanceOf(alice), 1000e6);
    }

    function test_FaucetMintsAtExactCap() public {
        uint256 cap = usdc.FAUCET_AMOUNT();
        vm.prank(alice);
        usdc.faucet(cap);
        assertEq(usdc.balanceOf(alice), cap);
    }

    function test_FaucetZeroAmountSucceeds() public {
        vm.prank(alice);
        usdc.faucet(0);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.totalSupply(), 0);
    }

    function test_FaucetCallableMultipleTimes() public {
        vm.startPrank(alice);
        usdc.faucet(1000e6);
        usdc.faucet(2000e6);
        vm.stopPrank();
        assertEq(usdc.balanceOf(alice), 3000e6);
    }

    // ─── faucet error path ───────────────────────────────────────────────────

    function test_FaucetRevertsAboveCap() public {
        uint256 overCap = usdc.FAUCET_AMOUNT() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                MockUSDC.FaucetAmountExceedsLimit.selector, overCap, usdc.FAUCET_AMOUNT()
            )
        );
        vm.prank(alice);
        usdc.faucet(overCap);
    }

    // ─── mint (owner-only) ───────────────────────────────────────────────────

    function test_MintAsOwnerCreditsRecipient() public {
        usdc.mint(alice, 500e6);
        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function test_MintLargeAmountAsOwner() public {
        usdc.mint(bob, 1_000_000e6);
        assertEq(usdc.balanceOf(bob), 1_000_000e6);
    }

    function test_MintRevertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        usdc.mint(alice, 1e6);
    }

    // ─── ERC-20 transfer / approve ───────────────────────────────────────────

    function test_TransferBetweenAccounts() public {
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        bool success = usdc.transfer(address(this), 400e6);
        assertTrue(success);
        assertEq(usdc.balanceOf(alice), 600e6);
        assertEq(usdc.balanceOf(address(this)), 400e6);
    }

    function test_ApproveAndTransferFrom() public {
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(bob, 300e6);
        assertEq(usdc.allowance(alice, bob), 300e6);

        vm.prank(bob);
        usdc.transferFrom(alice, bob, 300e6);

        assertEq(usdc.balanceOf(alice), 700e6);
        assertEq(usdc.balanceOf(bob), 300e6);
        assertEq(usdc.allowance(alice, bob), 0);
    }

    // ─── Fuzz ────────────────────────────────────────────────────────────────

    /// @dev Any amount within cap must succeed and credit the caller.
    function testFuzz_FaucetWithinCap(uint256 amount) public {
        amount = bound(amount, 0, usdc.FAUCET_AMOUNT());
        vm.prank(alice);
        usdc.faucet(amount);
        assertEq(usdc.balanceOf(alice), amount);
    }

    /// @dev Any amount above cap must revert with FaucetAmountExceedsLimit.
    function testFuzz_FaucetAboveCap(uint256 amount) public {
        amount = bound(amount, usdc.FAUCET_AMOUNT() + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockUSDC.FaucetAmountExceedsLimit.selector, amount, usdc.FAUCET_AMOUNT()
            )
        );
        vm.prank(alice);
        usdc.faucet(amount);
    }

    /// @dev Owner can mint any amount; recipient balance equals the minted amount.
    function testFuzz_MintAsOwner(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        usdc.mint(recipient, amount);
        assertEq(usdc.balanceOf(recipient), amount);
    }
}
