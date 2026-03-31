// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { PerpEngine, PositionHealthy, ZeroAddress } from "src/PerpEngine.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { Settlement } from "src/Settlement.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";
import { IPriceOracle } from "src/interfaces/IPriceOracle.sol";
import { ISettlement } from "src/interfaces/ISettlement.sol";

/// @title ProductionFixture
/// @notice Shared test fixture that deploys the full production stack
///         (MockUSDC -> Settlement -> PriceOracle -> PerpEngine) and
///         provides deterministic helpers for oracle observation seeding,
///         TWAP-aware price ramping, and collateral management.
///
///         All PerpEngine-adjacent tests (unit, fuzz, invariant) inherit
///         this fixture so TWAP + staleness are active by default.
abstract contract ProductionFixture is Test {
    // ── Deployed contracts ──────────────────────────────────────────
    MockUSDC internal usdc;
    MockPriceFeed internal feed;
    PriceOracle internal priceOracle;
    Settlement internal settlement;
    PerpEngine internal engine;

    // ── Standard actors ─────────────────────────────────────────────
    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    // ── Constants ───────────────────────────────────────────────────
    uint256 internal constant PRICE_2K = 2_000e8;
    uint256 internal constant COLLATERAL = 1_000e6;
    uint256 internal constant LEVERAGE = 10;
    uint256 internal constant HOUSE_RESERVE = 100_000e6;

    /// @dev Deploy the full stack with TWAP observations seeded so
    ///      `priceOracle.getPrice()` works from the first test call.
    function setUp() public virtual {
        // Deploy stack
        usdc = new MockUSDC();
        feed = new MockPriceFeed(int256(PRICE_2K));
        priceOracle = new PriceOracle(address(feed));
        settlement = new Settlement(address(usdc), address(0));
        engine = new PerpEngine(address(priceOracle), address(settlement), address(usdc));
        settlement.setEngine(address(engine));

        // Fund house reserve
        usdc.mint(owner, HOUSE_RESERVE);
        usdc.approve(address(settlement), HOUSE_RESERVE);
        settlement.fundHouseReserve(HOUSE_RESERVE);

        // Seed TWAP so oracle works with getPrice() from the start.
        // Record one observation at the initial price. This means
        // TWAP is active and deviation checks are enforced.
        seedTwapActive(PRICE_2K);
    }

    // ── USDC helpers ────────────────────────────────────────────────

    /// @dev Mint USDC to `trader` and approve Settlement.
    function fundAndApprove(address trader, uint256 amount) internal {
        usdc.mint(trader, amount);
        vm.prank(trader);
        usdc.approve(address(settlement), amount);
    }

    /// @dev Fund the house reserve with additional USDC.
    function fundHouseReserve(uint256 amount) internal {
        usdc.mint(owner, amount);
        usdc.approve(address(settlement), amount);
        settlement.fundHouseReserve(amount);
    }

    // ── Oracle / TWAP helpers ───────────────────────────────────────

    /// @dev Advance time by `dt` seconds and record an observation.
    ///      `dt` MUST be >0 (observations deduplicate by updatedAt).
    ///      Refreshes the feed's updatedAt so the oracle sees a fresh
    ///      timestamp (calling setPrice sets updatedAt = block.timestamp).
    function warpAndRecord(uint256 dt) internal {
        require(dt > 0, "warpAndRecord: dt must be > 0");
        vm.warp(block.timestamp + dt);
        (int256 currentPrice,) = feed.latestAnswer();
        feed.setPrice(currentPrice);
        priceOracle.recordObservation();
    }

    /// @dev Seed `n` observations at `price`, each `dt` seconds apart.
    function seedObservations(uint256 n, uint256 dt, uint256 price) internal {
        feed.setPrice(int256(price));
        for (uint256 i; i < n; ++i) {
            priceOracle.recordObservation();
            if (i < n - 1) {
                vm.warp(block.timestamp + dt);
                feed.setPrice(int256(price));
            }
        }
    }

    /// @dev Minimal TWAP seeding: records 1 observation so TWAP is
    ///      active (getPrice enforces deviation checks from here on).
    function seedTwapActive(uint256 price) internal {
        feed.setPrice(int256(price));
        priceOracle.recordObservation();
    }

    /// @dev Ramp the feed price from `fromPrice` to `toPrice` over
    ///      `totalDuration` seconds in `steps` increments. Each step
    ///      warps time, sets price, and records an observation so the
    ///      TWAP tracks the gradual price movement.
    ///      Handles both upward (fromPrice < toPrice) and downward
    ///      (fromPrice > toPrice) ramps without underflow.
    function rampPrice(uint256 fromPrice, uint256 toPrice, uint256 totalDuration, uint256 steps)
        internal
    {
        require(steps > 0, "rampPrice: steps must be > 0");
        uint256 dt = totalDuration / steps;
        require(dt > 0, "rampPrice: dt must be > 0");

        bool isUp = toPrice >= fromPrice;
        uint256 delta = isUp ? toPrice - fromPrice : fromPrice - toPrice;

        for (uint256 i = 1; i <= steps; ++i) {
            uint256 stepDelta = delta * i / steps;
            uint256 price = isUp ? fromPrice + stepDelta : fromPrice - stepDelta;
            vm.warp(block.timestamp + dt);
            feed.setPrice(int256(price));
            priceOracle.recordObservation();
        }
    }

    /// @dev Set the oracle price to `target` by first warping past the
    ///      TWAP window to drop old observations, then seeding 10 fresh
    ///      observations (filling the entire ring buffer) at `target`.
    ///      After this call, TWAP = target = spot, so `getPrice()` will
    ///      accept any deviation up to 3% from `target`.
    ///
    ///      Use this when the test needs to jump to an arbitrary price
    ///      regardless of the current TWAP state.
    function setOraclePrice(uint256 target) internal {
        // Warp past TWAP_WINDOW so all previous observations expire
        vm.warp(block.timestamp + 31);
        seedObservations(10, 2, target);
    }

    // ── Price-bounds helper ─────────────────────────────────────────

    /// @dev Build PriceBounds with 0.1% tolerance.
    function tightBounds(uint256 price) internal view returns (IPerpEngine.PriceBounds memory) {
        return IPerpEngine.PriceBounds({
            expectedPrice: price, maxDeviation: price / 1000, deadline: block.timestamp + 60
        });
    }

    /// @dev Build PriceBounds with very wide tolerance (accepts any
    ///      oracle price up to 2x the expected).
    function wideBounds(uint256 price) internal view returns (IPerpEngine.PriceBounds memory) {
        return IPerpEngine.PriceBounds({
            expectedPrice: price, maxDeviation: price, deadline: block.timestamp + 3600
        });
    }
}
