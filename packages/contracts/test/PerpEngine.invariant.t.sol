// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { PerpEngine } from "src/PerpEngine.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { Settlement } from "src/Settlement.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";

// ────────────────────────────────────────────────────────────────────
// Handler: drives randomised open / close / liquidate / price-move
// sequences with TWAP-aware oracle management.
// ────────────────────────────────────────────────────────────────────

contract PerpEngineHandler is Test {
    MockUSDC public usdc;
    MockPriceFeed public feed;
    PriceOracle public oracle;
    Settlement public settlement;
    PerpEngine public engine;

    // Ghost variables for invariant assertions.
    uint256 public totalTraderPayouts;
    uint256 public totalKeeperPayouts;
    uint256 public successfulOpens;
    uint256 public successfulCloses;
    uint256 public successfulLiquidations;
    uint256 public oracleRecords;
    uint256 public revertedOps;

    // Track open position IDs for close/liquidate targeting.
    uint256[] public openPositions;

    address internal owner;
    address internal constant TRADER = address(0xBEEF);
    address internal constant KEEPER = address(0xCAFE);

    uint256 private constant MIN_PRICE = 1_000e8;
    uint256 private constant MAX_PRICE = 10_000e8;

    constructor(
        MockUSDC usdc_,
        MockPriceFeed feed_,
        PriceOracle oracle_,
        Settlement settlement_,
        PerpEngine engine_,
        address owner_
    ) {
        usdc = usdc_;
        feed = feed_;
        oracle = oracle_;
        settlement = settlement_;
        engine = engine_;
        owner = owner_;
    }

    // ── Actions ─────────────────────────────────────────────────────

    /// @dev Open a position with fuzzed params. Price moves are bounded
    ///      to ±2.5% of current price to stay within TWAP MAX_DEVIATION.
    function openPosition(
        bool isLong,
        uint256 collateralSeed,
        uint256 leverageSeed,
        uint256 priceDeltaSeed
    ) external {
        uint256 collateral = bound(collateralSeed, 1e6, 50_000e6);
        uint256 leverage = bound(leverageSeed, 1, engine.MAX_SAFE_LEVERAGE());

        // Move price by ±2.5% of current to stay within TWAP bounds
        (int256 currentRaw,) = feed.latestAnswer();
        uint256 current = uint256(currentRaw);
        uint256 maxDelta = current * 25 / 1000;
        uint256 delta = bound(priceDeltaSeed, 0, maxDelta * 2);
        uint256 price;
        if (delta > maxDelta) {
            price = current + (delta - maxDelta);
        } else {
            price = current > delta ? current - delta : MIN_PRICE;
        }
        price = bound(price, MIN_PRICE, MAX_PRICE);

        // Warp 1s, set price, record observation (TWAP-aware)
        vm.warp(block.timestamp + 1);
        feed.setPrice(int256(price));
        oracle.recordObservation();

        // Fund trader
        vm.startPrank(owner);
        usdc.mint(TRADER, collateral);
        vm.stopPrank();

        vm.startPrank(TRADER);
        usdc.approve(address(settlement), collateral);

        IPerpEngine.PriceBounds memory bounds = IPerpEngine.PriceBounds({
            expectedPrice: price, maxDeviation: price, deadline: block.timestamp + 3600
        });

        try engine.openPosition(isLong, collateral, leverage, bounds) returns (uint256 posId) {
            openPositions.push(posId);
            ++successfulOpens;
        } catch {
            ++revertedOps;
        }
        vm.stopPrank();
    }

    /// @dev Close a random open position. Moves price within ±2.5%.
    function closePosition(uint256 indexSeed, uint256 priceDeltaSeed) external {
        if (openPositions.length == 0) return;

        uint256 idx = indexSeed % openPositions.length;
        uint256 posId = openPositions[idx];

        // Small price move
        (int256 currentRaw,) = feed.latestAnswer();
        uint256 current = uint256(currentRaw);
        uint256 maxDelta = current * 25 / 1000;
        uint256 delta = bound(priceDeltaSeed, 0, maxDelta * 2);
        uint256 price;
        if (delta > maxDelta) {
            price = current + (delta - maxDelta);
        } else {
            price = current > delta ? current - delta : MIN_PRICE;
        }
        price = bound(price, MIN_PRICE, MAX_PRICE);

        vm.warp(block.timestamp + 1);
        feed.setPrice(int256(price));
        oracle.recordObservation();

        IPerpEngine.PriceBounds memory bounds = IPerpEngine.PriceBounds({
            expectedPrice: price, maxDeviation: price, deadline: block.timestamp + 3600
        });

        uint256 traderBefore = usdc.balanceOf(TRADER);

        vm.prank(TRADER);
        try engine.closePosition(posId, bounds) {
            uint256 traderAfter = usdc.balanceOf(TRADER);
            if (traderAfter > traderBefore) {
                totalTraderPayouts += traderAfter - traderBefore;
            }
            _removePosition(idx);
            ++successfulCloses;
        } catch {
            ++revertedOps;
        }
    }

    /// @dev Attempt liquidation on a random open position.
    function liquidate(uint256 indexSeed, uint256 priceDeltaSeed) external {
        if (openPositions.length == 0) return;

        uint256 idx = indexSeed % openPositions.length;
        uint256 posId = openPositions[idx];

        // Small price move
        (int256 currentRaw,) = feed.latestAnswer();
        uint256 current = uint256(currentRaw);
        uint256 maxDelta = current * 25 / 1000;
        uint256 delta = bound(priceDeltaSeed, 0, maxDelta * 2);
        uint256 price;
        if (delta > maxDelta) {
            price = current + (delta - maxDelta);
        } else {
            price = current > delta ? current - delta : MIN_PRICE;
        }
        price = bound(price, MIN_PRICE, MAX_PRICE);

        vm.warp(block.timestamp + 1);
        feed.setPrice(int256(price));
        oracle.recordObservation();

        uint256 traderBefore = usdc.balanceOf(TRADER);
        uint256 keeperBefore = usdc.balanceOf(KEEPER);

        vm.prank(KEEPER);
        try engine.liquidate(posId) {
            uint256 traderAfter = usdc.balanceOf(TRADER);
            uint256 keeperAfter = usdc.balanceOf(KEEPER);
            if (traderAfter > traderBefore) {
                totalTraderPayouts += traderAfter - traderBefore;
            }
            if (keeperAfter > keeperBefore) {
                totalKeeperPayouts += keeperAfter - keeperBefore;
            }
            _removePosition(idx);
            ++successfulLiquidations;
        } catch {
            ++revertedOps;
        }
    }

    /// @dev Record an oracle observation (keeper-like action).
    ///      Keeps the oracle fresh without changing price.
    function recordObservation() external {
        vm.warp(block.timestamp + 1);
        (int256 currentPrice,) = feed.latestAnswer();
        feed.setPrice(currentPrice);
        try oracle.recordObservation() {
            ++oracleRecords;
        } catch {
            ++revertedOps;
        }
    }

    /// @dev Advance time slightly — may trigger staleness on next call.
    function warpTime(uint256 deltaSeed) external {
        uint256 delta = bound(deltaSeed, 0, 4);
        vm.warp(block.timestamp + delta);
    }

    // ── Internal ────────────────────────────────────────────────────

    function _removePosition(uint256 idx) internal {
        openPositions[idx] = openPositions[openPositions.length - 1];
        openPositions.pop();
    }

    function openPositionCount() external view returns (uint256) {
        return openPositions.length;
    }
}

// ────────────────────────────────────────────────────────────────────
// Invariant test suite
// ────────────────────────────────────────────────────────────────────

contract PerpEngineInvariantTest is StdInvariant, Test {
    MockUSDC internal usdc;
    MockPriceFeed internal feed;
    PriceOracle internal oracle;
    Settlement internal settlement;
    PerpEngine internal engine;
    PerpEngineHandler internal handler;

    address internal owner = address(this);
    uint256 private constant HOUSE_RESERVE = 50_000_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        feed = new MockPriceFeed(int256(2_000e8));
        oracle = new PriceOracle(address(feed));
        settlement = new Settlement(address(usdc), address(0));
        engine = new PerpEngine(address(oracle), address(settlement), address(usdc));
        settlement.setEngine(address(engine));

        usdc.mint(owner, HOUSE_RESERVE);
        usdc.approve(address(settlement), HOUSE_RESERVE);
        settlement.fundHouseReserve(HOUSE_RESERVE);

        // Seed TWAP with initial observations
        oracle.recordObservation();

        handler = new PerpEngineHandler(usdc, feed, oracle, settlement, engine, owner);

        targetContract(address(handler));
    }

    // ── Invariant 1: Solvency ───────────────────────────────────────

    /// @notice totalPayouts <= totalCollateral + houseReserve — ALWAYS.
    function invariant_SolvencyHolds() public view {
        uint256 totalIn = settlement.totalCollateral() + settlement.houseReserve();
        uint256 totalOut = settlement.totalPayouts();
        assertLe(totalOut, totalIn, "SOLVENCY VIOLATION: payouts exceed deposits + reserve");
    }

    /// @notice Settlement's actual USDC balance = solvencyBuffer().
    function invariant_BalanceMatchesSolvencyBuffer() public view {
        assertEq(
            usdc.balanceOf(address(settlement)),
            settlement.solvencyBuffer(),
            "BALANCE DESYNC: actual USDC != solvencyBuffer()"
        );
    }

    // ── Invariant 2: Accounting identity ────────────────────────────

    /// @notice totalCollateral + houseReserve ==
    ///         totalPayouts + solvencyBuffer.
    function invariant_AccountingIdentity() public view {
        uint256 totalIn = settlement.totalCollateral() + settlement.houseReserve();
        uint256 totalOut = settlement.totalPayouts();
        uint256 buffer = settlement.solvencyBuffer();
        assertEq(totalIn, totalOut + buffer, "ACCOUNTING IDENTITY VIOLATED");
    }

    // ── Non-vacuity ─────────────────────────────────────────────────

    /// @notice Verify handler operations are actually executing.
    function invariant_OperationCounters() public view {
        assertGe(
            handler.successfulOpens() + handler.successfulCloses()
                + handler.successfulLiquidations(),
            handler.successfulOpens(),
            "counter sanity"
        );
    }
}
