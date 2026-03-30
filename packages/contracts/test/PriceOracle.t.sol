// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { IPriceOracle } from "src/interfaces/IPriceOracle.sol";

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockPriceFeed public feed;

    uint256 private constant INITIAL_PRICE = 2000e8; // 8 decimals (1e8 = $1.00)

    /// @dev Block timestamp at setUp — feed.updatedAt is set here by MockPriceFeed constructor.
    uint256 private feedInitTime;

    function setUp() public {
        feedInitTime = block.timestamp;
        feed = new MockPriceFeed(int256(INITIAL_PRICE));
        oracle = new PriceOracle(address(feed));
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    function test_ZeroAddressConstructorReverts() public {
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        new PriceOracle(address(0));
    }

    // ─── Freshness ───────────────────────────────────────────────────────────

    function test_FreshPriceReturnsCorrectly() public view {
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, feedInitTime);
    }

    function test_StalePriceReverts() public {
        feed.setUpdatedAt(feedInitTime);
        vm.warp(feedInitTime + 6 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, feedInitTime, block.timestamp)
        );
        oracle.getPrice();
    }

    function test_PriceAtStalenessThresholdBoundary() public {
        feed.setUpdatedAt(feedInitTime);
        vm.warp(feedInitTime + 5 seconds);
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, feedInitTime);
    }

    function test_PriceJustBeyondStalenessThresholdReverts() public {
        feed.setUpdatedAt(feedInitTime);
        vm.warp(feedInitTime + 5 seconds + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, feedInitTime, block.timestamp)
        );
        oracle.getPrice();
    }

    // ─── Invalid price ───────────────────────────────────────────────────────

    function test_NegativePriceReverts() public {
        feed.setPrice(-1);
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.InvalidPrice.selector, int256(-1)));
        oracle.getPrice();
    }

    function test_ZeroPriceReverts() public {
        feed.setPrice(0);
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.InvalidPrice.selector, int256(0)));
        oracle.getPrice();
    }

    function test_NegativePriceRevertsOnRecord() public {
        feed.setPrice(-1);
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.InvalidPrice.selector, int256(-1)));
        oracle.recordObservation();
    }

    // ─── recordObservation ───────────────────────────────────────────────────

    function test_RecordObservationStoresPrice() public {
        oracle.recordObservation();

        // Move forward and record another observation
        vm.warp(feedInitTime + 10 seconds);
        feed.setPrice(int256(2040e8)); // 2% above — within MAX_DEVIATION
        oracle.recordObservation();

        // TWAP = (2000+2040)/2 = 2020e8; spot = 2040e8; dev = 20/2020*10000 ≈ 99bps < 300
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2040e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_RecordObservationWithStaleDataReverts() public {
        // Advance past genesis so block.timestamp - 6 seconds doesn't underflow
        vm.warp(feedInitTime + 100 seconds);
        uint256 staleTime = block.timestamp - 6 seconds;
        feed.setUpdatedAt(staleTime);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, staleTime, block.timestamp)
        );
        oracle.recordObservation();
    }

    // ─── TWAP — happy path ───────────────────────────────────────────────────

    function test_NoObservationsReturnsCurrentPrice() public view {
        // Before any recordObservation call, TWAP check is skipped (bootstrapping).
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
        assertEq(updatedAt, feedInitTime);
    }

    function test_TWAPAveragingWithMultipleObservations() public {
        // Prices stay within 1% of each other — within MAX_DEVIATION.
        feed.setPrice(int256(2000e8));
        oracle.recordObservation();

        vm.warp(feedInitTime + 10 seconds);
        feed.setPrice(int256(2001e8));
        oracle.recordObservation();

        vm.warp(feedInitTime + 20 seconds);
        feed.setPrice(int256(2002e8));
        oracle.recordObservation();

        // TWAP = (2000+2001+2002)/3 = 2001e8; spot = 2002e8; dev = 1/2001*10000 ≈ 5bps
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2002e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_TWAPWindowFiltersOldObservations() public {
        // An old observation outside the TWAP window is excluded.
        feed.setPrice(int256(1000e8));
        oracle.recordObservation(); // recorded at feedInitTime

        vm.warp(feedInitTime + 40 seconds); // 40s later — beyond TWAP_WINDOW

        feed.setPrice(int256(2000e8));
        oracle.recordObservation(); // the only observation in the 30s window

        // TWAP = 2000e8 (single in-window observation); spot = 2000e8; dev = 0
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2000e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_MultipleObservationsWithinWindow() public {
        // All 3 observations and spot price are within 0.1% of each other.
        feed.setPrice(int256(2000e8));
        oracle.recordObservation();

        vm.warp(feedInitTime + 10 seconds);
        feed.setPrice(int256(2001e8));
        oracle.recordObservation();

        vm.warp(feedInitTime + 20 seconds);
        feed.setPrice(int256(2002e8));
        oracle.recordObservation();

        // TWAP = 2001e8; spot = 2002e8; deviation ≈ 5bps < 300bps
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, 2002e8);
        assertEq(updatedAt, block.timestamp);
    }

    function test_ObservationRingBufferWrapsAround() public {
        // Record 11 observations — ring capacity is 10, so index 0 gets overwritten.
        // Prices use a 0.02e8 step (0.001%) to stay well within MAX_DEVIATION.
        for (uint256 i; i < 11; ++i) {
            feed.setPrice(int256(2000e8 + int256(i * 2e6)));
            oracle.recordObservation();
            if (i < 10) vm.warp(block.timestamp + 1 seconds);
        }

        uint256 expectedFinalPrice = 2000e8 + 10 * 2e6;

        // TWAP ≈ average of all 10 ring slots ≈ 2000.11e8; dev from 2000.20e8 ≈ 4bps
        (uint256 price, uint256 updatedAt) = oracle.getPrice();
        assertEq(price, expectedFinalPrice);
        assertEq(updatedAt, block.timestamp);
    }

    // ─── TWAP — error paths ──────────────────────────────────────────────────

    function test_InsufficientObservationsReverts() public {
        // Record one observation, then advance past the TWAP window.
        oracle.recordObservation(); // recorded at feedInitTime

        vm.warp(feedInitTime + 31 seconds); // all observations now older than TWAP_WINDOW
        feed.setPrice(int256(INITIAL_PRICE)); // keep feed fresh

        vm.expectRevert(IPriceOracle.InsufficientObservations.selector);
        oracle.getPrice();
    }

    function test_PriceDeviationExceedsMaxReverts() public {
        // Record a baseline observation at 2000e8.
        oracle.recordObservation();

        // Set spot price 5% higher than the recorded TWAP — exceeds MAX_DEVIATION of 3%.
        uint256 newPrice = 2100e8; // 5% above 2000e8
        feed.setPrice(int256(newPrice));

        // TWAP = 2000e8; spot = 2100e8; deviationBps = 500 > 300
        uint256 expectedDevBps = (newPrice - INITIAL_PRICE) * 10_000 / INITIAL_PRICE; // 500
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceOracle.PriceDeviationExceedsMax.selector,
                newPrice,
                INITIAL_PRICE,
                expectedDevBps
            )
        );
        oracle.getPrice();
    }

    // ─── Future timestamp (underflow guard) ─────────────────────────────────

    function test_FutureTimestampGetPriceReverts() public {
        // A feed reporting updatedAt in the future must revert with StalePrice,
        // not panic via arithmetic underflow.
        feed.setUpdatedAt(block.timestamp + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceOracle.StalePrice.selector, block.timestamp + 1, block.timestamp
            )
        );
        oracle.getPrice();
    }

    function test_FutureTimestampRecordObservationReverts() public {
        feed.setUpdatedAt(block.timestamp + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceOracle.StalePrice.selector, block.timestamp + 1, block.timestamp
            )
        );
        oracle.recordObservation();
    }

    // ─── Deduplication ───────────────────────────────────────────────────────

    function test_DuplicateObservationIsNoOp() public {
        // First call records observation.
        oracle.recordObservation();
        // Second call with same feed updatedAt is silently ignored — no ring slot consumed.
        oracle.recordObservation();

        // Only one slot should be occupied (observationCount is private; verify via TWAP path:
        // after 31s all observations would be stale, which requires count > 0 at some point).
        // Verify getPrice still succeeds (TWAP has 1 obs, spot == twap, dev = 0).
        (uint256 price,) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
    }

    function test_NewFeedTimestampAfterDuplicate() public {
        oracle.recordObservation(); // obs[0] at feedInitTime

        // Advance feed timestamp by 5s and record — should succeed (different updatedAt).
        vm.warp(feedInitTime + 5 seconds);
        feed.setPrice(int256(INITIAL_PRICE)); // updates feed._updatedAt = block.timestamp
        oracle.recordObservation(); // obs[1] at feedInitTime+5

        // TWAP = INITIAL_PRICE; spot = INITIAL_PRICE; dev = 0 ✅
        (uint256 price,) = oracle.getPrice();
        assertEq(price, INITIAL_PRICE);
    }

    // ─── Constants / immutables ──────────────────────────────────────────────

    function test_ConstantsAreCorrect() public view {
        assertEq(oracle.STALENESS_THRESHOLD(), 5 seconds);
        assertEq(oracle.TWAP_WINDOW(), 30 seconds);
        assertEq(oracle.MAX_DEVIATION(), 300);
    }

    function test_FeedAddressIsImmutable() public view {
        assertEq(address(oracle.feed()), address(feed));
    }

    // ─── Fuzz ────────────────────────────────────────────────────────────────

    /// @dev Any age within staleness threshold succeeds; any beyond reverts with StalePrice.
    ///      Uses full abi.encodeWithSelector since StalePrice carries parameters.
    function testFuzz_StalenessCheck(uint256 age) public {
        age = bound(age, 0, 100 seconds);
        feed.setUpdatedAt(feedInitTime);
        vm.warp(feedInitTime + age);

        if (age <= oracle.STALENESS_THRESHOLD()) {
            (uint256 price,) = oracle.getPrice();
            assertEq(price, INITIAL_PRICE);
        } else {
            // feedUpdatedAt = feedInitTime; block.timestamp = feedInitTime + age
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPriceOracle.StalePrice.selector, feedInitTime, feedInitTime + age
                )
            );
            oracle.getPrice();
        }
    }

    /// @dev Any strictly negative int256 price must revert with InvalidPrice (never wrap).
    function testFuzz_NegativePriceReverts(uint256 rawNeg) public {
        rawNeg = bound(rawNeg, 1, uint256(type(int256).max));
        int256 negPrice = -int256(rawNeg);
        feed.setPrice(negPrice);
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.InvalidPrice.selector, negPrice));
        oracle.getPrice();
    }

    /// @dev Spot prices within MAX_DEVIATION bps of TWAP succeed; beyond revert.
    ///      Uses full error encoding since PriceDeviationExceedsMax carries parameters.
    function testFuzz_DeviationBoundary(uint256 deviationBps) public {
        deviationBps = bound(deviationBps, 0, 600); // 0-6%
        oracle.recordObservation(); // TWAP = INITIAL_PRICE

        // New price = INITIAL_PRICE * (1 + deviationBps / 10_000); integer arithmetic is exact
        // because INITIAL_PRICE (2000e8) * any deviationBps ≤ 600 fits in uint256 cleanly.
        uint256 newPrice = INITIAL_PRICE + INITIAL_PRICE * deviationBps / 10_000;
        feed.setPrice(int256(newPrice));

        // actualDev mirrors the contract's own calculation: deviation * BPS_DENOMINATOR / twap
        uint256 actualDev = (newPrice - INITIAL_PRICE) * 10_000 / INITIAL_PRICE;

        if (actualDev <= oracle.MAX_DEVIATION()) {
            (uint256 price,) = oracle.getPrice();
            assertEq(price, newPrice);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPriceOracle.PriceDeviationExceedsMax.selector,
                    newPrice,
                    INITIAL_PRICE,
                    actualDev
                )
            );
            oracle.getPrice();
        }
    }
}
