// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { MockUSDC } from "src/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC internal usdc;
    address internal alice = makeAddr("alice");

    function setUp() public {
        usdc = new MockUSDC();
    }

    function test_name() public view {
        assertEq(usdc.name(), "Mock USD Coin");
    }

    function test_symbol() public view {
        assertEq(usdc.symbol(), "USDC");
    }

    function test_decimals() public view {
        assertEq(usdc.decimals(), 6);
    }

    function test_faucet() public {
        vm.prank(alice);
        usdc.faucet(1000e6);
        assertEq(usdc.balanceOf(alice), 1000e6);
    }

    function test_mint() public {
        usdc.mint(alice, 500e6);
        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function test_transfer() public {
        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        bool success = usdc.transfer(address(this), 400e6);
        assertTrue(success);
        assertEq(usdc.balanceOf(alice), 600e6);
        assertEq(usdc.balanceOf(address(this)), 400e6);
    }

    function testFuzz_faucet(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        vm.prank(alice);
        usdc.faucet(amount);
        assertEq(usdc.balanceOf(alice), amount);
    }
}
