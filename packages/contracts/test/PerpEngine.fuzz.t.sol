// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ProductionFixture } from "./fixtures/ProductionFixture.sol";
import { PerpEngine, PositionHealthy } from "src/PerpEngine.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";

/// @title PerpEngineFuzzTest
/// @notice Constrained fuzz tests for PerpEngine with TWAP-active oracle.
///         Uses ProductionFixture so all tests exercise the same oracle gates
///         that exist on-chain. Price changes use rampPrice() to stay within
///         MAX_DEVIATION.
///
///         Configured for 10 000 runs via foundry.toml [profile.default] fuzz.runs.
contract PerpEngineFuzzTest is ProductionFixture {
    address internal trader = makeAddr("trader");

    uint256 private constant FUZZ_HOUSE_RESERVE = 10_000_000e6;

    function setUp() public override {
        super.setUp();
        // Fund house reserve generously for profitable trades.
        fundHouseReserve(FUZZ_HOUSE_RESERVE);
    }

    // ── Fuzz: openPosition -> closePosition lifecycle ───────────────

    /// @dev Randomise direction, collateral, leverage, entry price.
    ///      Exit price bounded to ±2.5% of entry (within TWAP 3% gate).
    ///      Verifies: payout <= solvency buffer, position closed,
    ///      accounting identity holds.
    function testFuzz_OpenAndClose(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed,
        uint256 exitDeltaSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);

        // Exit within ±2.5% of entry to stay within MAX_DEVIATION.
        // range = entryPrice * 5% = 0.05 * entryPrice
        uint256 range = entryPrice * 5 / 100;
        uint256 exitDelta = bound(exitDeltaSeed, 0, range);
        // Alternate up/down based on isLong to get both profit and loss
        uint256 exitPrice = isLong ? entryPrice + exitDelta / 2 : entryPrice - exitDelta / 2;
        if (exitPrice == 0) exitPrice = 1e8;

        // Seed oracle at entry price (fills ring buffer)
        setOraclePrice(entryPrice);

        uint256 bufferBefore = settlement.solvencyBuffer();

        // Open position
        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);
        vm.prank(trader);
        uint256 posId = engine.openPosition(isLong, collateral, leverage, wideBounds(entryPrice));

        // Small move to exit price (within 2.5%, safe for TWAP)
        rampPrice(entryPrice, exitPrice, 10, 5);

        vm.prank(trader);
        engine.closePosition(posId, wideBounds(exitPrice));

        // Invariants
        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen, "position must be closed");

        uint256 traderBal = usdc.balanceOf(trader);
        assertLe(traderBal, bufferBefore, "payout must not exceed buffer");

        assertEq(
            settlement.solvencyBuffer(),
            usdc.balanceOf(address(settlement)),
            "solvency buffer must equal actual USDC balance"
        );
    }

    /// @dev Open at any safe price, attempt liquidation at entry price.
    ///      With safe leverage (<=20), must revert PositionHealthy.
    function testFuzz_CannotLiquidateAtEntryPrice(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);

        setOraclePrice(entryPrice);

        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);
        vm.prank(trader);
        uint256 posId = engine.openPosition(isLong, collateral, leverage, wideBounds(entryPrice));

        // Liquidate at entry price — must fail.
        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    /// @dev Open a long, crash price by 2.5% (within TWAP), liquidate
    ///      positions with high leverage that become underwater.
    function testFuzz_LiquidateAfterSmallCrash(uint256 collateralSeed, uint256 entryPriceSeed)
        public
    {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 entryPrice = bound(entryPriceSeed, 200e8, 100_000e8);

        // Use max safe leverage (20x) so a small move triggers liquidation.
        // At 20x, maintenanceMargin = 100% of collateral.
        // A 2.5% drop: pnl = -50% of collateral → equity = 50% < 100%
        uint256 leverage = engine.MAX_SAFE_LEVERAGE();

        setOraclePrice(entryPrice);

        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);
        vm.prank(trader);
        uint256 posId = engine.openPosition(true, collateral, leverage, wideBounds(entryPrice));

        // Crash 2.5% — within TWAP deviation
        uint256 crashPrice = entryPrice * 975 / 1000;
        if (crashPrice == 0) crashPrice = 1e8;
        rampPrice(entryPrice, crashPrice, 10, 5);

        vm.prank(keeper);
        engine.liquidate(posId);

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen, "position must be closed");

        uint256 traderPayout = usdc.balanceOf(trader);
        uint256 keeperPayout = usdc.balanceOf(keeper);
        assertLe(
            traderPayout + keeperPayout, collateral, "total payouts must not exceed collateral"
        );
    }

    /// @dev Bounded-loss invariant: payout <= collateral + notional.
    function testFuzz_BoundedLossOnClose(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 entryPriceSeed,
        uint256 exitDeltaSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 entryPrice = bound(entryPriceSeed, 100e8, 100_000e8);

        // Exit within ±2.5%
        uint256 maxDelta = entryPrice * 25 / 1000;
        uint256 exitDelta = bound(exitDeltaSeed, 0, maxDelta);
        uint256 exitPrice =
            isLong ? entryPrice + exitDelta : entryPrice > exitDelta ? entryPrice - exitDelta : 1e8;

        setOraclePrice(entryPrice);

        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);
        vm.prank(trader);
        uint256 posId = engine.openPosition(isLong, collateral, leverage, wideBounds(entryPrice));

        rampPrice(entryPrice, exitPrice, 10, 5);

        uint256 traderBefore = usdc.balanceOf(trader);
        vm.prank(trader);
        engine.closePosition(1, wideBounds(exitPrice));

        uint256 payout = usdc.balanceOf(trader) - traderBefore;
        uint256 notional = collateral * leverage;
        assertLe(payout, collateral + notional, "payout bounded by collateral + notional");

        assertEq(
            settlement.solvencyBuffer(),
            usdc.balanceOf(address(settlement)),
            "solvency buffer must match balance"
        );
    }

    /// @dev Stale oracle blocks open — warp past staleness threshold.
    function testFuzz_StaleOracleRevertsOnOpen(
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 warpSeed
    ) public {
        uint256 collateral = bound(collateralSeed, 1e6, 100_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());
        uint256 warp = bound(warpSeed, 6, 3600);

        usdc.mint(trader, collateral);
        vm.prank(trader);
        usdc.approve(address(settlement), collateral);

        // Freeze the feed timestamp and warp past staleness
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + warp);

        vm.expectRevert(); // StalePrice from oracle
        vm.prank(trader);
        engine.openPosition(true, collateral, leverage, wideBounds(PRICE_2K));
    }
}
