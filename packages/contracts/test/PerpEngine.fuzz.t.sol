// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { PerpEngine, PositionHealthy } from "src/PerpEngine.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { Settlement } from "src/Settlement.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";

/// @title PerpEngineFuzzTest
/// @notice Constrained fuzz tests for the full PerpEngine lifecycle.
///         Configured for 10 000 runs via foundry.toml [profile.default] fuzz.runs.
///         Covers: open, close, liquidate with randomised collateral, leverage, prices.
contract PerpEngineFuzzTest is Test {
    MockUSDC internal usdc;
    MockPriceFeed internal feed;
    PriceOracle internal oracle;
    Settlement internal settlement;
    PerpEngine internal engine;

    address internal owner = address(this);
    address internal trader = makeAddr("trader");
    address internal keeper = makeAddr("keeper");

    uint256 private constant HOUSE_RESERVE = 10_000_000e6; // 10M USDC

    function setUp() public {
        usdc = new MockUSDC();
        feed = new MockPriceFeed(int256(2_000e8));
        oracle = new PriceOracle(address(feed));
        settlement = new Settlement(address(usdc), address(0));
        engine = new PerpEngine(address(oracle), address(settlement), address(usdc));
        settlement.setEngine(address(engine));

        // Fund house reserve generously so profitable trades always pay out.
        usdc.mint(owner, HOUSE_RESERVE);
        usdc.approve(address(settlement), HOUSE_RESERVE);
        settlement.fundHouseReserve(HOUSE_RESERVE);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _bounds(uint256 price) internal view returns (IPerpEngine.PriceBounds memory) {
        return IPerpEngine.PriceBounds({
            expectedPrice: price,
            maxDeviation: price, // very wide — accept any oracle price up to 2×
            deadline: block.timestamp + 3600
        });
    }

    function _open(bool isLong, uint256 collateral, uint256 leverage, uint256 entryPrice)
        internal
        returns (uint256 posId)
    {
        feed.setPrice(int256(entryPrice));
        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);
        vm.prank(trader);
        posId = engine.openPosition(isLong, collateral, leverage, _bounds(entryPrice));
    }

    // ─── Fuzz: openPosition → closePosition lifecycle ─────────────────────────

    /// @dev Randomise direction, collateral, leverage, entry/exit prices.
    ///      After close, verify: payout ≥ 0 (implicit), payout ≤ solvency buffer,
    ///      position is no longer open.
    ///      Exit price bounded to ±50% of entry to keep max profit within house reserve.
    function testFuzz_OpenAndClose(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed,
        uint256 exitPriceSeed
    ) public {
        // ── Constrain inputs to realistic ranges ──────────────────────────────
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6); // 1–100k USDC
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE()); // 1–20×
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8); // $100–$100k
        // ±50% of entry keeps max pnl = collateral × leverage × 0.5 = 10× max collateral,
        // which fits comfortably within the 10M house reserve.
        uint256 exitPrice = bound(exitPriceSeed, entryPrice / 2, entryPrice * 3 / 2);

        uint256 bufferBefore = settlement.solvencyBuffer();

        // ── Open ──────────────────────────────────────────────────────────────
        uint256 posId = _open(isLong, collateral, leverage, entryPrice);

        // ── Close at exit price ───────────────────────────────────────────────
        feed.setPrice(int256(exitPrice));
        vm.prank(trader);
        engine.closePosition(posId, _bounds(exitPrice));

        // ── Invariants ────────────────────────────────────────────────────────
        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen, "position must be closed");

        // Payout never exceeds pre-close solvency buffer.
        uint256 traderBal = usdc.balanceOf(trader);
        assertLe(traderBal, bufferBefore, "payout must not exceed buffer");

        // Settlement accounting is consistent.
        assertEq(
            settlement.solvencyBuffer(),
            usdc.balanceOf(address(settlement)),
            "solvency buffer must equal actual USDC balance"
        );
    }

    /// @dev Open a position, then attempt liquidation at the same entry price.
    ///      With safe leverage (≤20), equity ≥ maintenanceMargin at entry → must revert PositionHealthy.
    function testFuzz_CannotLiquidateAtEntryPrice(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);

        uint256 posId = _open(isLong, collateral, leverage, entryPrice);

        // Liquidate at entry price — must fail.
        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    /// @dev Open a position, crash the price to near-zero, then liquidate.
    ///      After liquidation: position closed, trader payout + keeper reward ≤ collateral,
    ///      solvency invariant holds.
    function testFuzz_LiquidateAfterCrash(
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 2, engine.MAX_SAFE_LEVERAGE()); // ≥2 so crash triggers liq
        uint256 entryPrice = bound(entryPriceSeed, 200e8, 100_000e8);

        // Open a long — crashing the price will make it liquidatable.
        uint256 posId = _open(true, collateral, leverage, entryPrice);

        // Crash price by enough to breach maintenance margin.
        // Required: equity < maintenanceMargin → price drop > (1 - 5%×leverage/100%) × entryPrice
        // For any leverage ≥2 with 5% margin, a 50% drop always triggers liquidation.
        uint256 crashPrice = entryPrice / 2;
        if (crashPrice == 0) crashPrice = 1e8; // floor at $1
        feed.setPrice(int256(crashPrice));

        // Liquidate.
        vm.prank(keeper);
        engine.liquidate(posId);

        // Invariants.
        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen, "position must be closed after liquidation");

        uint256 traderPayout = usdc.balanceOf(trader);
        uint256 keeperPayout = usdc.balanceOf(keeper);
        assertLe(
            traderPayout + keeperPayout,
            collateral,
            "total payouts from liquidated position must not exceed collateral"
        );
    }

    /// @dev Bounded-loss: trader payout ≤ collateral + notional (max possible profit).
    ///      Exit price bounded ±50% of entry to keep profits within house reserve.
    function testFuzz_BoundedLossOnClose(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed,
        uint256 exitPriceSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);
        uint256 exitPrice = bound(exitPriceSeed, entryPrice / 2, entryPrice * 3 / 2);

        uint256 posId = _open(isLong, collateral, leverage, entryPrice);

        feed.setPrice(int256(exitPrice));
        uint256 traderBefore = usdc.balanceOf(trader);
        vm.prank(trader);
        engine.closePosition(posId, _bounds(exitPrice));

        uint256 payout = usdc.balanceOf(trader) - traderBefore;

        // Real bounded-loss check: payout ≤ collateral + notional (max 100% profit).
        uint256 notional = collateral * leverage;
        assertLe(payout, collateral + notional, "payout bounded by collateral + notional");

        // Solvency buffer matches actual USDC held.
        assertEq(
            settlement.solvencyBuffer(),
            usdc.balanceOf(address(settlement)),
            "solvency buffer must match balance"
        );
    }

    /// @dev Stale oracle edge case: price must be fresh for open.
    ///      Warp past staleness threshold, attempt open, expect revert from oracle.
    function testFuzz_StaleOracleRevertsOnOpen(
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed,
        uint256 warpSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);
        uint256 warp = bound(warpSeed, 6, 3600); // 6s–1hr past staleness

        feed.setPrice(int256(entryPrice));
        feed.setUpdatedAt(block.timestamp);
        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);

        vm.warp(block.timestamp + warp);

        vm.expectRevert(); // oracle reverts with StalePrice
        vm.prank(trader);
        engine.openPosition(true, collateral, leverage, _bounds(entryPrice));
    }
}
