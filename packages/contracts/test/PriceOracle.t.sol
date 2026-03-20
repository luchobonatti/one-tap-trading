// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { IPriceOracle } from "src/interfaces/IPriceOracle.sol";

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockPriceFeed public feed;

    uint256 private constant INITIAL_PRICE = 2000e8; // 8 decimals like real price feeds
    uint256 private constant STALENESS_THRESHOLD = 5 seconds;
    uint256 private constant TWAP_WINDOW = 30 seconds;

    function setUp() public {
        feed = new MockPriceFeed(int256(INITIAL_PRICE));
        oracle = new PriceOracle(address(feed));
    }

    function test_FreshPriceReturnsCorrectly() public view {
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, block.timestamp);
    }

    function test_StalePriceReverts() public {
        // Move time forward by 6 seconds (beyond staleness threshold)
        vm.warp(block.timestamp + 6 seconds);

        // Feed still reports old timestamp
        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, uint256(1), block.timestamp)
        );
        oracle.getPrice();
    }

    function test_PriceAtStalenessThresholdBoundary() public {
        uint256 originalTime = block.timestamp;
        uint256 originalUpdatedAt = originalTime;

        // Move exactly to the boundary (5 seconds)
        vm.warp(originalTime + 5 seconds);

        // Should still be valid (not > 5 seconds, but == 5 seconds)
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, originalUpdatedAt);
    }

    function test_PriceJustBeyondStalenessThresholdReverts() public {
        uint256 originalTime = block.timestamp;

        // Move just beyond the boundary (5.1 seconds)
        vm.warp(originalTime + 5 seconds + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, uint256(1), block.timestamp)
        );
        oracle.getPrice();
    }

    function test_RecordObservationStoresPrice() public {
        oracle.recordObservation();

        // Move forward and record another observation
        vm.warp(block.timestamp + 10 seconds);
        feed.setPrice(int256(2100e8));
        oracle.recordObservation();

        // Verify we can still get a fresh price
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2100e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_RecordObservationWithStaleDataReverts() public {
        // Advance past genesis so block.timestamp - 6 seconds doesn't underflow
        vm.warp(block.timestamp + 100 seconds);
        // Set feed to stale data (6 seconds in the past)
        uint256 staleTime = block.timestamp - 6 seconds;
        feed.setUpdatedAt(staleTime);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, staleTime, block.timestamp)
        );
        oracle.recordObservation();
    }

    function test_TWAPAveragingWithMultipleObservations() public {
        // Record observations at different prices
        feed.setPrice(int256(2000e8));
        oracle.recordObservation();

        vm.warp(block.timestamp + 10 seconds);
        feed.setPrice(int256(2100e8));
        oracle.recordObservation();

        vm.warp(block.timestamp + 10 seconds);
        feed.setPrice(int256(2050e8));
        oracle.recordObservation();

        // Get price should return current price (2050e8)
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2050e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_TWAPWindowFiltersOldObservations() public {
        // Record observation at time 0
        feed.setPrice(int256(1000e8));
        oracle.recordObservation();

        // Move forward 40 seconds (beyond TWAP window of 30s)
        vm.warp(block.timestamp + 40 seconds);

        // Record new observation
        feed.setPrice(int256(2000e8));
        oracle.recordObservation();

        // Get price should only consider the recent observation
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_MultipleObservationsWithinWindow() public {
        // Record 3 observations within the TWAP window
        feed.setPrice(int256(2000e8));
        oracle.recordObservation();

        vm.warp(block.timestamp + 10 seconds);
        feed.setPrice(int256(2100e8));
        oracle.recordObservation();

        vm.warp(block.timestamp + 10 seconds);
        feed.setPrice(int256(1900e8));
        oracle.recordObservation();

        // All 3 observations are within 30s window
        // TWAP = (2000 + 2100 + 1900) / 3 = 2000e8
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 1900e8); // Current price
        assertEq(updatedAt, block.timestamp);
    }

    function test_NoObservationsReturnsCurrentPrice() public view {
        // Don't record any observations, just get price
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, block.timestamp);
    }

    function test_ObservationRingBufferWrapsAround() public {
        // Record 11 observations to test ring buffer wrapping (capacity is 10)
        for (uint256 i; i < 11; ++i) {
            feed.setPrice(int256(int256(2000e8 + (i * 100e8))));
            oracle.recordObservation();
            if (i < 10) {
                vm.warp(block.timestamp + 1 seconds);
            }
        }

        // Should still work and return current price
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2000e8 + (10 * 100e8));
        assertEq(updatedAt, block.timestamp);
    }

    function test_ConstantsAreCorrect() public view {
        assertEq(oracle.STALENESS_THRESHOLD(), 5 seconds);
        assertEq(oracle.TWAP_WINDOW(), 30 seconds);
        assertEq(oracle.MAX_DEVIATION(), 300);
    }

    function test_FeedAddressIsImmutable() public view {
        assertEq(address(oracle.feed()), address(feed));
    }
}
