// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ProductionFixture } from "./fixtures/ProductionFixture.sol";
import { IPriceOracle } from "src/interfaces/IPriceOracle.sol";

/// @title PriceOracleRealTest
/// @notice Integration tests for PriceOracle with TWAP active.
///         Exercises the same oracle gates that exist on-chain:
///         STALENESS_THRESHOLD (5s), TWAP_WINDOW (30s), MAX_DEVIATION (300bps).
contract PriceOracleRealTest is ProductionFixture {
    // ── Scenario: Bootstrapped TWAP-active oracle allows small moves ─────

    /// @dev GIVEN spot=2000e8 with 1 observation, WHEN price moves to 2040e8 (2%),
    ///      THEN getPrice succeeds (200 bps <= 300 bps MAX_DEVIATION).
    function test_TwapActiveAllowsSmallMoves() public {
        // setUp already seeds TWAP at 2000e8
        uint256 newPrice = 2_040e8;
        vm.warp(block.timestamp + 1);
        feed.setPrice(int256(newPrice));

        (uint256 price,) = priceOracle.getPrice();
        assertEq(price, newPrice);
    }

    // ── Scenario: Keeper stopped -> TWAP check fails safe ────────────────

    /// @dev GIVEN 1 observation at t0, WHEN time advances 31s without recording,
    ///      THEN getPrice reverts InsufficientObservations.
    function test_KeeperStoppedRevertsSafe() public {
        // setUp recorded 1 observation at current timestamp
        vm.warp(block.timestamp + 31);
        feed.setPrice(int256(PRICE_2K)); // feed is fresh

        vm.expectRevert(IPriceOracle.InsufficientObservations.selector);
        priceOracle.getPrice();
    }

    // ── Scenario: Large jump exceeds MAX_DEVIATION ───────────────────────

    /// @dev GIVEN TWAP=2000e8, WHEN spot jumps to 2100e8 (5%),
    ///      THEN getPrice reverts PriceDeviationExceedsMax.
    function test_LargeJumpExceedsMaxDeviation() public {
        uint256 jumpPrice = 2_100e8; // 5% above TWAP
        feed.setPrice(int256(jumpPrice));

        uint256 expectedDev = (jumpPrice - PRICE_2K) * 10_000 / PRICE_2K; // 500bps
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceOracle.PriceDeviationExceedsMax.selector, jumpPrice, PRICE_2K, expectedDev
            )
        );
        priceOracle.getPrice();
    }

    // ── Scenario: Ramped price stays within deviation ────────────────────

    /// @dev GIVEN TWAP=2000e8, WHEN price ramps to 2040e8 over 10s (4 steps),
    ///      THEN getPrice succeeds because TWAP tracks the ramp.
    function test_RampedPriceStaysWithinDeviation() public {
        rampPrice(PRICE_2K, 2_040e8, 10, 4);

        (uint256 price,) = priceOracle.getPrice();
        assertEq(price, 2_040e8);
    }

    // ── Scenario: Stale feed reverts on getPrice ─────────────────────────

    /// @dev GIVEN feed updated at t0, WHEN 6s pass without feed update,
    ///      THEN getPrice reverts StalePrice.
    function test_StaleFeedRevertsOnGetPrice() public {
        uint256 feedTime = block.timestamp;
        feed.setUpdatedAt(feedTime);
        vm.warp(feedTime + 6);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, feedTime, block.timestamp)
        );
        priceOracle.getPrice();
    }

    // ── Scenario: Stale feed reverts on recordObservation ────────────────

    /// @dev Bad observations are never written to the ring buffer.
    function test_StaleFeedRevertsOnRecord() public {
        uint256 feedTime = block.timestamp;
        feed.setUpdatedAt(feedTime);
        vm.warp(feedTime + 6);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceOracle.StalePrice.selector, feedTime, block.timestamp)
        );
        priceOracle.recordObservation();
    }

    // ── Scenario: Multiple observations within window ────────────────────

    /// @dev Seeding 5 observations at the same price, then small move.
    function test_MultipleObservationsStabilizeTwap() public {
        seedObservations(5, 3, PRICE_2K);

        uint256 newPrice = 2_050e8; // 2.5% above base — within 3%
        vm.warp(block.timestamp + 1);
        feed.setPrice(int256(newPrice));

        (uint256 price,) = priceOracle.getPrice();
        assertEq(price, newPrice);
    }

    // ── Scenario: warpAndRecord helper advances TWAP ─────────────────────

    /// @dev Verify the helper correctly records observations.
    function test_WarpAndRecordAdvancesTwap() public {
        // Record a second observation 5s later
        warpAndRecord(5);

        // Price at TWAP=2000, spot=2000 — deviation 0, should work
        (uint256 price,) = priceOracle.getPrice();
        assertEq(price, PRICE_2K);
    }

    // ── Scenario: Deviation exactly at boundary (300bps) ─────────────────

    /// @dev 3% move with single observation in TWAP should be at the exact boundary.
    function test_DeviationExactlyAtBoundarySucceeds() public {
        // TWAP has 1 observation at 2000e8
        // 3% of 2000 = 60 => new price = 2060e8
        uint256 boundaryPrice = 2_060e8;
        feed.setPrice(int256(boundaryPrice));

        // Deviation = 60/2000 * 10000 = 300bps = MAX_DEVIATION (<=, so success)
        (uint256 price,) = priceOracle.getPrice();
        assertEq(price, boundaryPrice);
    }

    /// @dev 3% + 1 unit exceeds the boundary.
    function test_DeviationJustAboveBoundaryReverts() public {
        // 301 bps: delta = 2000e8 * 301 / 10000 = 60.2e8
        // Use 2061e8 which gives deviationBps = 61/2000*10000 = 305 > 300
        uint256 overPrice = 2_061e8;
        feed.setPrice(int256(overPrice));

        uint256 expectedDev = (overPrice - PRICE_2K) * 10_000 / PRICE_2K;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceOracle.PriceDeviationExceedsMax.selector, overPrice, PRICE_2K, expectedDev
            )
        );
        priceOracle.getPrice();
    }
}
