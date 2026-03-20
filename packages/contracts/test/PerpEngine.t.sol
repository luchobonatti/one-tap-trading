// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { PerpEngine, PositionHealthy, ZeroAddress } from "src/PerpEngine.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { Settlement } from "src/Settlement.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";
import { ISettlement } from "src/interfaces/ISettlement.sol";

/// @dev Full integration test suite for PerpEngine.
///      Deploys the complete stack: MockUSDC → Settlement → PriceOracle → PerpEngine.
contract PerpEngineTest is Test {
    MockUSDC internal usdc;
    MockPriceFeed internal feed;
    PriceOracle internal priceOracle;
    Settlement internal settlement;
    PerpEngine internal engine;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    // Prices in 8-decimal units (1e8 = $1.00)
    uint256 private constant PRICE_2K = 2_000e8;
    uint256 private constant PRICE_2100 = 2_100e8;
    uint256 private constant PRICE_1900 = 1_900e8;

    // Collateral / leverage
    uint256 private constant COLLATERAL = 1_000e6; // 1 000 USDC
    uint256 private constant LEVERAGE = 10;

    // House reserve to cover trader profits
    uint256 private constant HOUSE_RESERVE = 100_000e6; // 100k USDC

    function setUp() public {
        // Deploy stack
        usdc = new MockUSDC();
        feed = new MockPriceFeed(int256(PRICE_2K));
        priceOracle = new PriceOracle(address(feed));
        settlement = new Settlement(address(usdc), address(0)); // engine set below
        engine = new PerpEngine(address(priceOracle), address(settlement), address(usdc));

        // Wire: tell Settlement which engine is authorised
        settlement.setEngine(address(engine));

        // Fund house reserve so profitable trades can be paid out
        usdc.mint(owner, HOUSE_RESERVE);
        usdc.approve(address(settlement), HOUSE_RESERVE);
        settlement.fundHouseReserve(HOUSE_RESERVE);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Give alice USDC and approve Settlement.
    function _fundAlice(uint256 amount) internal {
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(settlement), amount);
    }

    /// @dev Build tight price bounds around a price (±0.1%).
    function _tightBounds(uint256 price) internal view returns (IPerpEngine.PriceBounds memory) {
        return IPerpEngine.PriceBounds({
            expectedPrice: price,
            maxDeviation: price / 1000, // 0.1%
            deadline: block.timestamp + 60
        });
    }

    /// @dev Open a long position for alice at `price` with standard params.
    function _openLong(uint256 price) internal returns (uint256 posId) {
        feed.setPrice(int256(price));
        _fundAlice(COLLATERAL);
        vm.prank(alice);
        posId = engine.openPosition(true, COLLATERAL, LEVERAGE, _tightBounds(price));
    }

    /// @dev Open a short position for alice at `price` with standard params.
    function _openShort(uint256 price) internal returns (uint256 posId) {
        feed.setPrice(int256(price));
        _fundAlice(COLLATERAL);
        vm.prank(alice);
        posId = engine.openPosition(false, COLLATERAL, LEVERAGE, _tightBounds(price));
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    function test_ConstructorSetsImmutables() public view {
        assertEq(address(engine.oracle()), address(priceOracle));
        assertEq(address(engine.settlement()), address(settlement));
        assertEq(address(engine.usdc()), address(usdc));
        assertEq(engine.nextPositionId(), 1);
    }

    function test_ConstructorZeroAddressReverts() public {
        // ZeroAddress — not Unauthorized — is the correct error for constructor param validation.
        vm.expectRevert(ZeroAddress.selector);
        new PerpEngine(address(0), address(settlement), address(usdc));
    }

    // ─── openPosition ─────────────────────────────────────────────────────────

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
        feed.setPrice(int256(PRICE_2K));
        _fundAlice(COLLATERAL);
        vm.expectEmit(true, true, false, false, address(engine));
        emit IPerpEngine.PositionOpened(1, alice, true, COLLATERAL, LEVERAGE, PRICE_2K);
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, LEVERAGE, _tightBounds(PRICE_2K));
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
        engine.openPosition(true, 0, LEVERAGE, _tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsBelowMinCollateral() public {
        uint256 tooSmall = engine.MIN_COLLATERAL() - 1;
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidCollateral.selector, tooSmall));
        vm.prank(alice);
        engine.openPosition(true, tooSmall, LEVERAGE, _tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsZeroLeverage() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, 0));
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, 0, _tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsExcessiveLeverage() public {
        uint256 overMax = engine.MAX_LEVERAGE() + 1;
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, overMax));
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, overMax, _tightBounds(PRICE_2K));
    }

    function test_OpenPositionRevertsUnsafeLeverage() public {
        // leverage = MAX_SAFE_LEVERAGE + 1 (= 21) makes equity < maintenanceMargin at entry price,
        // so a keeper can liquidate the position in the same block. Must revert with InvalidLeverage.
        uint256 unsafeLeverage = engine.MAX_SAFE_LEVERAGE() + 1;
        _fundAlice(COLLATERAL);
        vm.expectRevert(
            abi.encodeWithSelector(IPerpEngine.InvalidLeverage.selector, unsafeLeverage)
        );
        vm.prank(alice);
        engine.openPosition(true, COLLATERAL, unsafeLeverage, _tightBounds(PRICE_2K));
    }

    function test_OpenPositionAtMaxSafeLeverageNotImmediatelyLiquidatable() public {
        // leverage = MAX_SAFE_LEVERAGE (20): at entry price, equity = collateral = maintenanceMargin.
        // The position is at the exact boundary — NOT below — so liquidate must revert PositionHealthy.
        uint256 maxSafe = engine.MAX_SAFE_LEVERAGE();
        feed.setPrice(int256(PRICE_2K));
        _fundAlice(COLLATERAL);
        vm.prank(alice);
        uint256 posId = engine.openPosition(true, COLLATERAL, maxSafe, _tightBounds(PRICE_2K));

        // Liquidating at the entry price must fail — position is not underwater.
        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_OpenPositionRevertsDeadlineExpired() public {
        feed.setPrice(int256(PRICE_2K));
        _fundAlice(COLLATERAL);
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
        feed.setPrice(int256(PRICE_2100)); // oracle at 2100
        _fundAlice(COLLATERAL);
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

    // ─── getPosition ─────────────────────────────────────────────────────────

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

    // ─── closePosition ────────────────────────────────────────────────────────

    function test_CloseLongProfitPaysOut() public {
        uint256 posId = _openLong(PRICE_2K);

        // Exit at 2100: +5% price, 10× leverage → +50% pnl
        // PnL = 1000 USDC × 10 × (2100 - 2000) / 2000 = 500 USDC
        feed.setPrice(int256(PRICE_2100));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2100));

        assertEq(usdc.balanceOf(alice), 1_500e6); // 1000 collateral + 500 profit
    }

    function test_CloseLongLossCapsAtCollateral() public {
        uint256 posId = _openLong(PRICE_2K);

        // Exit at 1900: −5% price, 10× leverage → −50% pnl
        // PnL = 1000 × 10 × (2000 - 1900) / 2000 = 500 USDC loss → pays 500
        feed.setPrice(int256(PRICE_1900));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_1900));

        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function test_CloseLongTotalLossPayoutIsZero() public {
        uint256 posId = _openLong(PRICE_2K);

        // Price drops 20%: PnL = 1000 × 10 × 400 / 2000 = 2000 loss > collateral → pays 0
        uint256 crashPrice = 1_600e8;
        feed.setPrice(int256(crashPrice));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(crashPrice));

        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_CloseShortProfit() public {
        uint256 posId = _openShort(PRICE_2K);

        // Short profits when price falls
        feed.setPrice(int256(PRICE_1900));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_1900));

        assertEq(usdc.balanceOf(alice), 1_500e6);
    }

    function test_CloseShortLoss() public {
        uint256 posId = _openShort(PRICE_2K);

        // Short loses when price rises
        feed.setPrice(int256(PRICE_2100));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2100));

        assertEq(usdc.balanceOf(alice), 500e6);
    }

    function test_ClosePositionEmitsEvent() public {
        uint256 posId = _openLong(PRICE_2K);
        feed.setPrice(int256(PRICE_2100));
        int256 expectedPnl = int256(COLLATERAL * LEVERAGE * (PRICE_2100 - PRICE_2K) / PRICE_2K);

        vm.expectEmit(true, true, false, true, address(engine));
        emit IPerpEngine.PositionClosed(posId, alice, PRICE_2100, expectedPnl);
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2100));
    }

    function test_ClosePositionMarksAsNotOpen() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2K));

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_ClosePositionRevertsForNonTrader() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionNotFound.selector, posId));
        vm.prank(bob);
        engine.closePosition(posId, _tightBounds(PRICE_2K));
    }

    function test_ClosePositionRevertsDoubleClose() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2K));

        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionAlreadyClosed.selector, posId));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2K));
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
        feed.setPrice(int256(PRICE_2100));
        IPerpEngine.PriceBounds memory tight = IPerpEngine.PriceBounds({
            expectedPrice: PRICE_2K, maxDeviation: 1, deadline: block.timestamp + 60
        });
        vm.expectRevert(
            abi.encodeWithSelector(IPerpEngine.PriceOutOfBounds.selector, PRICE_2100, PRICE_2K, 1)
        );
        vm.prank(alice);
        engine.closePosition(posId, tight);
    }

    // ─── liquidate ────────────────────────────────────────────────────────────

    function test_LiquidateHealthyPositionReverts() public {
        uint256 posId = _openLong(PRICE_2K);
        // Price unchanged — position is healthy
        vm.expectRevert(abi.encodeWithSelector(PositionHealthy.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateUnderwaterPositionSucceeds() public {
        uint256 posId = _openLong(PRICE_2K);

        // 5% drop with 10× leverage = 50% loss on notional.
        // Maintenance margin = 5% × notional = 5% × 10_000 USDC = 500 USDC
        // Equity at 1900: collateral + pnl = 1000 - 500 = 500 USDC = maintenanceMargin → NOT liquidatable
        // Equity at 1800: 1000 × 10 × (2000-1800)/2000 = 1000 loss > collateral → equity = 0 < margin
        uint256 crashPrice = 1_800e8;
        feed.setPrice(int256(crashPrice));

        vm.prank(keeper);
        engine.liquidate(posId);

        IPerpEngine.Position memory pos = engine.getPosition(posId);
        assertFalse(pos.isOpen);
    }

    function test_LiquidateKeeperGetsReward() public {
        uint256 posId = _openLong(PRICE_2K);
        uint256 crashPrice = 1_800e8; // position fully underwater
        feed.setPrice(int256(crashPrice));

        vm.prank(keeper);
        engine.liquidate(posId);

        // Keeper reward = 1% of collateral = 10 USDC (equity=0, capped to 0)
        // Actually at crashPrice pnl = -1000, equity = 0 → keeper reward = min(10, 0) = 0
        // Keeper gets nothing when position is fully wiped out
        assertEq(usdc.balanceOf(keeper), 0);
    }

    function test_LiquidateKeeperRewardFromPartialEquity() public {
        // Long with 20× leverage:
        //   maintenanceMargin = collateral × leverage × 5% = 1000 × 20 × 5% = 1000 USDC
        //   At exitP = 1990: pnl = 1000 × 20 × (2000-1990)/2000 = -100 → equity = 900 < 1000 → liquidatable
        //   keeper reward = 1% × collateral = 10 USDC (< equity) → traderPayout = 890 USDC
        uint256 posLeverage = 20;
        uint256 entryP = 2_000e8;
        uint256 exitP = 1_990e8;

        feed.setPrice(int256(entryP));
        _fundAlice(COLLATERAL);
        vm.prank(alice);
        uint256 posId = engine.openPosition(true, COLLATERAL, posLeverage, _tightBounds(entryP));

        feed.setPrice(int256(exitP));
        vm.prank(keeper);
        engine.liquidate(posId);

        assertEq(usdc.balanceOf(keeper), 10e6);
        assertEq(usdc.balanceOf(alice), 890e6);
    }

    function test_LiquidateEmitsEvent() public {
        uint256 posId = _openLong(PRICE_2K);
        uint256 crashPrice = 1_800e8;
        feed.setPrice(int256(crashPrice));

        vm.expectEmit(true, true, false, true, address(engine));
        emit IPerpEngine.PositionLiquidated(posId, alice, crashPrice);
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateRevertsAlreadyClosed() public {
        uint256 posId = _openLong(PRICE_2K);
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(PRICE_2K));

        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionAlreadyClosed.selector, posId));
        vm.prank(keeper);
        engine.liquidate(posId);
    }

    function test_LiquidateRevertsNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(IPerpEngine.PositionNotFound.selector, 999));
        vm.prank(keeper);
        engine.liquidate(999);
    }

    // ─── PnL invariants ───────────────────────────────────────────────────────

    function test_TraderPayoutNeverExceedsCollateralPlusProfit() public {
        uint256 posId = _openLong(PRICE_2K);
        uint256 gainPrice = 2_200e8;
        feed.setPrice(int256(gainPrice));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(gainPrice));

        // PnL = 1000 × 10 × 200/2000 = 1000. Payout = 2000 USDC.
        assertEq(usdc.balanceOf(alice), 2_000e6);
    }

    function test_TraderPayoutIsZeroOnTotalWipeout() public {
        uint256 posId = _openLong(PRICE_2K);
        // Drop 11%+: loss > collateral → payout = 0
        uint256 wipePrice = 1_780e8;
        feed.setPrice(int256(wipePrice));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(wipePrice));

        assertEq(usdc.balanceOf(alice), 0);
    }

    // ─── Fuzz ────────────────────────────────────────────────────────────────

    /// @dev For any exit price, payout never exceeds the settlement's pre-close solvency buffer.
    ///      This is the hard economic bound: we can never pay out more than we have.
    function testFuzz_LongPayoutNeverExceedsBuffer(uint256 exitPriceSeed) public {
        uint256 exitPrice = bound(exitPriceSeed, 1e8, 10_000e8); // $1 – $100 000
        uint256 posId = _openLong(PRICE_2K);

        uint256 bufferBefore = settlement.solvencyBuffer();
        feed.setPrice(int256(exitPrice));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(exitPrice));

        // Payout (uint256) is implicitly ≥ 0.
        // Payout cannot exceed the buffer that existed before close.
        assertLe(usdc.balanceOf(alice), bufferBefore);
    }

    /// @dev Short position: payout similarly bounded by the pre-close solvency buffer.
    function testFuzz_ShortPayoutNeverExceedsBuffer(uint256 exitPriceSeed) public {
        uint256 exitPrice = bound(exitPriceSeed, 1e8, 10_000e8);
        uint256 posId = _openShort(PRICE_2K);

        uint256 bufferBefore = settlement.solvencyBuffer();
        feed.setPrice(int256(exitPrice));
        vm.prank(alice);
        engine.closePosition(posId, _tightBounds(exitPrice));

        assertLe(usdc.balanceOf(alice), bufferBefore);
    }
}
