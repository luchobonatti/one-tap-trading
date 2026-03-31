// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ProductionFixture } from "./fixtures/ProductionFixture.sol";
import { PerpEngine, PositionHealthy, ZeroAddress } from "src/PerpEngine.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";
import { IPriceOracle } from "src/interfaces/IPriceOracle.sol";

/// @title PerpEngineTest
/// @notice Full integration test suite for PerpEngine with TWAP-active oracle.
///         Uses ProductionFixture so every test exercises the same oracle gates
///         that exist on-chain (STALENESS_THRESHOLD, TWAP_WINDOW, MAX_DEVIATION).
///
///         Price changes >3% of TWAP use `rampPrice()` to stay within MAX_DEVIATION.
contract PerpEngineTest is ProductionFixture {
    // ── Additional price constants ──────────────────────────────────
    uint256 private constant PRICE_2100 = 2_100e8;
    uint256 private constant PRICE_1900 = 1_900e8;

    // ── Helpers ─────────────────────────────────────────────────────

    /// @dev Open a long for alice at current feed price. Assumes TWAP
    ///      has been ramped to `price` before calling this.
    function _openLong(uint256 price) internal returns (uint256 posId) {
        fundAndApprove(alice, COLLATERAL);
        vm.prank(alice);
        posId = engine.openPosition(true, COLLATERAL, LEVERAGE, tightBounds(price));
    }

    /// @dev Open a short for alice at current feed price.
    function _openShort(uint256 price) internal returns (uint256 posId) {
        fundAndApprove(alice, COLLATERAL);
        vm.prank(alice);
        posId = engine.openPosition(false, COLLATERAL, LEVERAGE, tightBounds(price));
    }

    /// @dev Ramp the oracle from `from` to `to`, then open a long.
    function _rampAndOpenLong(uint256 from, uint256 to) internal returns (uint256 posId) {
        rampPrice(from, to, 30, 10);
        posId = _openLong(to);
    }

    // ─── Constructor ────────────────────────────────────────────────

    function test_ConstructorSetsImmutables() public view {
        assertEq(address(engine.oracle()), address(priceOracle));
        assertEq(address(engine.settlement()), address(settlement));
        assertEq(address(engine.usdc()), address(usdc));
        assertEq(engine.nextPositionId(), 1);
    }

    function test_ConstructorZeroAddressReverts() public {
        vm.expectRevert(ZeroAddress.selector);
        new PerpEngine(address(0), address(settlement), address(usdc));
    }

    // ─── openPosition ───────────────────────────────────────────────

    function test_OpenLongStoresPosition() public {
        uint256 posId = _openLong(PRICE_2K);

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertEq(pos.trader, alice);
        assertTrue(pos.isLong);
        assertEq(pos.collateral, COLLATERAL);
        assertEq(pos.leverage, LEVERAGE);
        assertEq(pos.entryPrice, PRICE_2K);
        assertEq(pos.timestamp, block.timestamp);
        assertTrue(pos.isOpen);
    }

    function test_OpenShortStoresPosition() public {
        uint256 posId = _openShort(PRICE_2K);

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isLong);
        assertTrue(pos.isOpen);
    }

    function test_OpenPositionEscrowsCollateral() public {
        _openLong(PRICE_2K);
        assertEq(usdc.balanceOf(address(settlement)), HOUSE_RESERVE + COLLATERAL);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_OpenPositionEmitsEvent() public {
        fundAndApprove(alice, COLLATERAL);
        vm.expectEmit(true, true, false, false, address(engine));
        emit IPerpEngine.PositionOpened(1, alice, true, COLLATERAL, LEVERAGE, PRICE_2K);
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, tightBounds(PRICE_2K));
    }

    function test_OpenPositionIncrementsId() public {
        uint256 id1 = _openLong(PRICE_2K);
        uint256 id2 = _openLong(PRICE_2K);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(engine.nextPositionId(), 3);
    }

    function test_OpenPositionRevertsZeroCollateral() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidCollateral.selector, 0));
        vm.prank(alice);
        engine.openPosition(true, 0, LEVERAGE, tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsBelowMinCollateral() public {
        uint256 tooSmall = engine.MIN_COLLATERAL() - 1;
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidCollateral.selector, tooSmall));
        vm.prank(alice);
        engine.openPosition(true, tooSmall, LEVERAGE, tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsZeroLeverage() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, 0));
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, 0, tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsExcessiveLeverage() public {
        uint256 overMax = engine.MAX_LEVERAGE() + 1;
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, overMax));
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, overMax, tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsUnsafeLeverage() public {
        uint256 unsafeLeverage = engine.MAX_SAFE_LEVERAGE() + 1;
        fundAndApprove(alice, COLLATERAL);
        vm.expectRevert(
            abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, unsafeLeverage)
        );
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, unsafeLeverage, tightBounds(PRICE_2K));
    }

    function test_OpenPositionAtMaxSafeLeverageNotLiquidatable() public {
        uint256 maxSafe = engine.MAX_SAFE_LEVERAGE();
        fundAndApprove(alice, COLLATERAL);
        vm.prank(alice);
        uint256 posId = engine.openPosition(true, COLLATERAL, maxSafe, tightBounds(PRICE_2K));

        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_OpenPositionRevertsDeadlineExpired() public {
        fundAndApprove(alice, COLLATERAL);
        IPerpEngine.PriceBounds memory expired = IPerpEngine.PriceBounds({
            expectedPrice: PRICE_2K, maxDeviation: PRICE_2K / 1000, deadline: block.timestamp - 1
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IPerpEngine.DeadlineExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, expired);
    }

    function test_OpenPositionRevertsPriceOutOfBounds() public {
        // Ramp price to 2100 so oracle returns 2100 (within TWAP deviation)
        rampPrice(PRICE_2K, PRICE_2100, 30, 10);
        fundAndApprove(alice, COLLATERAL);
        // Caller expected 2000, tolerance ±1 (very tight)
        IPerpEngine.PriceBounds memory tight = IPerpEngine.PriceBounds({
            expectedPrice: PRICE_2K, maxDeviation: 1, deadline: block.timestamp + 60
        });
        vm.expectRevert(
            abi.encodeWithSelector(IPerpEngine.PriceOutOfBounds.selector, PRICE_2100, PRICE_2K, 1)
        );
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, tight);
    }

    // ─── getPosition ────────────────────────────────────────────────

    function test_GetPositionRevertsNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionNotFound.selector, 99));
        engine.getPosition(99);
    }

    function test_GetPositionReturnsFull() public {
        uint256 posId = _openLong(PRICE_2K);
        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertEq(pos.trader, alice);
        assertEq(pos.entryPrice, PRICE_2K);
        assertEq(pos.leverage, LEVERAGE);
        assertTrue(pos.isOpen);
    }

    // ─── closePosition ──────────────────────────────────────────────

    /// @dev Long profit: open at 2000, ramp to 2100 (+5%), close.
    ///      PnL = 1000 x 10 x (2100-2000)/2000 = 500 USDC.
    function test_CloseLongProfitPaysOut() public {
        uint256 posId = _openLong(PRICE_2K);

        // Ramp price from 2000 to 2100 — keeps TWAP within 3%
        rampPrice(PRICE_2K, PRICE_2100, 30, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2100));

        assertEq(usdc.balanceOf(alice), 1_500e6);
    }

    /// @dev Long loss: open at 2000, ramp down to 1900 (-5%), close.
    ///      PnL = -500 USDC, payout = 500.
    function test_CloseLongLossCapsAtCollateral() public {
        uint256 posId = _openLong(PRICE_2K);

        rampPrice(PRICE_2K, PRICE_1900, 30, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_1900));

        assertEq(usdc.balanceOf(alice), 500e6);
    }

    /// @dev Total wipeout: ramp to 1600 (-20%), PnL > collateral.
    ///      Large move requires many small steps so each step stays
    ///      within 3% TWAP deviation.
    function test_CloseLongTotalLossPayoutIsZero() public {
        uint256 posId = _openLong(PRICE_2K);

        uint256 crashPrice = 1_600e8;
        // 20% drop needs ~40 steps over 80s to keep each step < 3%
        rampPrice(PRICE_2K, crashPrice, 80, 40);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(crashPrice));

        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_CloseShortProfit() public {
        uint256 posId = _openShort(PRICE_2K);

        rampPrice(PRICE_2K, PRICE_1900, 30, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_1900));

        assertEq(usdc.balanceOf(alice), 1_500e6);
    }

    function test_CloseShortLoss() public {
        uint256 posId = _openShort(PRICE_2K);

        rampPrice(PRICE_2K, PRICE_2100, 30, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2100));

        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function test_ClosePositionEmitsEvent() public {
        uint256 posId = _openLong(PRICE_2K);

        rampPrice(PRICE_2K, PRICE_2100, 30, 10);

        int256 expectedPnl = int256(COLLATERAL * LEVERAGE * (PRICE_2100 - PRICE_2K) / PRICE_2K);
        vm.expectEmit(true, true, false, true, address(engine));
        emit IPerpEngine.PositionClosed(posId, alice, PRICE_2100, expectedPnl);
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2100));
    }

    function test_ClosePositionMarksAsNotOpen() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2K));

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_ClosePositionRevertsForNonTrader() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionNotFound.selector, posId));
        vm.prank(bob);
        engine.closePosition(posId, tightBounds(PRICE_2K));
    }

    function test_ClosePositionRevertsDoubleClose() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2K));

        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionAlreadyClosed.selector, posId));
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2K));
    }

    function test_ClosePositionRevertsDeadlineExpired() public {
        uint256 posId = _openLong(PRICE_2K);
        IPerpEngine.PriceBounds memory expired = IPerpEngine.PriceBounds({
            expectedPrice: PRICE_2K, maxDeviation: PRICE_2K / 1000, deadline: block.timestamp - 1
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IPerpEngine.DeadlineExpired.selector, block.timestamp - 1, block.timestamp
            )
        );
        vm.prank(alice);
        engine.closePosition(posId, expired);
    }

    function test_ClosePositionRevertsPriceOutOfBounds() public {
        uint256 posId = _openLong(PRICE_2K);
        rampPrice(PRICE_2K, PRICE_2100, 30, 10);
        IPerpEngine.PriceBounds memory tight = IPerpEngine.PriceBounds({
            expectedPrice: PRICE_2K, maxDeviation: 1, deadline: block.timestamp + 60
        });
        vm.expectRevert(
            abi.encodeWithSelector(IPerpEngine.PriceOutOfBounds.selector, PRICE_2100, PRICE_2K, 1)
        );
        vm.prank(alice);
        engine.closePosition(posId, tight);
    }

    // ─── liquidate ──────────────────────────────────────────────────

    function test_LiquidateHealthyPositionReverts() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateUnderwaterPositionSucceeds() public {
        uint256 posId = _openLong(PRICE_2K);

        // Ramp to 1800 (-10%): needs many steps to stay within 3%
        uint256 crashPrice = 1_800e8;
        rampPrice(PRICE_2K, crashPrice, 60, 30);

        vm.prank(keeper);
        engine.liquidate(posId);

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_LiquidateKeeperGetsZeroOnFullWipeout() public {
        uint256 posId = _openLong(PRICE_2K);
        uint256 crashPrice = 1_800e8;
        rampPrice(PRICE_2K, crashPrice, 60, 30);

        vm.prank(keeper);
        engine.liquidate(posId);

        // equity=0 at full wipeout → keeper reward capped to 0
        assertEq(usdc.balanceOf(keeper), 0);
    }

    function test_LiquidateKeeperRewardFromPartialEquity() public {
        // 20x leverage: maintenanceMargin = 1000 * 20 * 5% = 1000
        // At 1990: pnl = 1000*20*(2000-1990)/2000 = -100 → equity=900 < 1000
        // keeper reward = 1%*1000 = 10 USDC
        uint256 posLeverage = 20;

        fundAndApprove(alice, COLLATERAL);
        vm.prank(alice);
        uint256 posId = engine.openPosition(true, COLLATERAL, posLeverage, tightBounds(PRICE_2K));

        // Small ramp from 2000→1990 (0.5% move, well within 3%)
        rampPrice(PRICE_2K, 1_990e8, 10, 5);

        vm.prank(keeper);
        engine.liquidate(posId);

        assertEq(usdc.balanceOf(keeper), 10e6);
        assertEq(usdc.balanceOf(alice), 890e6);
    }

    function test_LiquidateEmitsEvent() public {
        uint256 posId = _openLong(PRICE_2K);
        uint256 crashPrice = 1_800e8;
        rampPrice(PRICE_2K, crashPrice, 60, 30);

        vm.expectEmit(true, true, false, true, address(engine));
        emit IPerpEngine.PositionLiquidated(posId, alice, crashPrice);
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateRevertsAlreadyClosed() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(PRICE_2K));

        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionAlreadyClosed.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateRevertsNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionNotFound.selector, 999));
        vm.prank(keeper);
        engine.liquidate(999);
    }

    // ─── E2E: Canonical trade flow (TWAP active) ────────────────────

    /// @dev Spec scenario: Long E2E profit (TWAP active)
    ///      approve → open → time → observe → close → payout
    function test_E2E_LongProfit() public {
        // 1. Alice gets USDC and approves Settlement
        fundAndApprove(alice, COLLATERAL);

        // 2. Open long at 2000
        vm.prank(alice);
        uint256 posId = engine.openPosition(true, COLLATERAL, LEVERAGE, tightBounds(PRICE_2K));

        // 3. Time passes, price ramps to 2060 (3% gain, within deviation)
        uint256 exitPrice = 2_060e8;
        rampPrice(PRICE_2K, exitPrice, 20, 10);

        // 4. Close position
        vm.prank(alice);
        engine.closePosition(posId, tightBounds(exitPrice));

        // 5. Verify payout
        // PnL = 1000 * 10 * (2060 - 2000) / 2000 = 300 USDC
        assertEq(usdc.balanceOf(alice), 1_300e6);
        assertFalse(engine.getPosition(posId).isOpen);
    }

    /// @dev Spec scenario: Short E2E profit (TWAP active)
    function test_E2E_ShortProfit() public {
        fundAndApprove(alice, COLLATERAL);

        vm.prank(alice);
        uint256 posId = engine.openPosition(false, COLLATERAL, LEVERAGE, tightBounds(PRICE_2K));

        // Price drops 3% → 1940
        uint256 exitPrice = 1_940e8;
        rampPrice(PRICE_2K, exitPrice, 20, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(exitPrice));

        // PnL = 1000 * 10 * (2000 - 1940) / 2000 = 300 USDC
        assertEq(usdc.balanceOf(alice), 1_300e6);
    }

    /// @dev Spec scenario: Stale oracle blocks trade
    function test_E2E_StaleOracleBlocksTrade() public {
        fundAndApprove(alice, COLLATERAL);

        // Freeze feed timestamp, warp past staleness
        feed.setUpdatedAt(block.timestamp);
        vm.warp(block.timestamp + 6);

        vm.expectRevert(); // StalePrice from oracle
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, tightBounds(PRICE_2K));
    }

    /// @dev Spec scenario: Large price jump blocks trade (TWAP deviation)
    function test_E2E_TwapDeviationBlocksTrade() public {
        fundAndApprove(alice, COLLATERAL);

        // Jump price 5% without ramping — TWAP deviation > 3%
        uint256 jumpPrice = 2_100e8;
        feed.setPrice(int256(jumpPrice));

        vm.expectRevert(); // PriceDeviationExceedsMax from oracle
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, tightBounds(jumpPrice));
    }

    // ─── PnL invariants ─────────────────────────────────────────────

    function test_TraderPayoutNeverExceedsCollateralPlusProfit() public {
        uint256 posId = _openLong(PRICE_2K);

        // Ramp to 2060 (3% gain within TWAP)
        uint256 gainPrice = 2_060e8;
        rampPrice(PRICE_2K, gainPrice, 20, 10);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(gainPrice));

        // PnL = 1000 * 10 * 60 / 2000 = 300. Payout = 1300.
        assertEq(usdc.balanceOf(alice), 1_300e6);
    }

    function test_TraderPayoutIsZeroOnTotalWipeout() public {
        uint256 posId = _openLong(PRICE_2K);

        // Ramp down to 1780 (-11%): needs many steps
        uint256 wipePrice = 1_780e8;
        rampPrice(PRICE_2K, wipePrice, 60, 30);

        vm.prank(alice);
        engine.closePosition(posId, tightBounds(wipePrice));

        assertEq(usdc.balanceOf(alice), 0);
    }
}
