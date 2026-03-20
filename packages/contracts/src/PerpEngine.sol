// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPerpEngine } from "./IPerpEngine.sol";
import { ISettlement } from "./interfaces/ISettlement.sol";
import { IPriceOracle } from "./interfaces/IPriceOracle.sol";

/// @title PerpEngine
/// @notice House-as-counterparty perpetual futures engine for One Tap Trading.
///
///         All USDC is held in Settlement; PerpEngine only stores position state.
///         Positions are opened/closed/liquidated against a PriceOracle that enforces
///         TWAP sanity and feed staleness. Callers supply PriceBounds on open/close to
///         protect against front-running; liquidation uses raw oracle price (protocol-
///         determined, not liquidator-controlled).
contract PerpEngine is IPerpEngine {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Minimum collateral per position (1 USDC, 6 decimals).
    uint256 public constant MIN_COLLATERAL = 1e6;

    /// @notice Maximum leverage multiplier (100×).
    uint256 public constant MAX_LEVERAGE = 100;

    /// @notice Maintenance margin rate in basis points (500 = 5%).
    ///         A position is liquidatable when equity < notional × maintenanceMarginBps / 10_000.
    uint256 public constant MAINTENANCE_MARGIN_BPS = 500;

    /// @notice Keeper reward as a fraction of collateral in basis points (100 = 1%).
    uint256 public constant KEEPER_REWARD_BPS = 100;

    uint256 private constant BPS_DENOM = 10_000;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice Oracle that provides TWAP-validated prices.
    IPriceOracle public immutable oracle;

    /// @notice Settlement escrow that holds all USDC.
    ISettlement public immutable settlement;

    /// @notice USDC token address (used only for ABI exposure / off-chain approval).
    IERC20 public immutable usdc;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Next position ID to assign. Starts at 1.
    uint256 public nextPositionId;

    /// @dev positionId → Position
    mapping(uint256 => Position) private _positions;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param oracle_     PriceOracle address.
    /// @param settlement_ Settlement escrow address.
    /// @param usdc_       MockUSDC (or production USDC) token address.
    constructor(address oracle_, address settlement_, address usdc_) {
        if (oracle_ == address(0) || settlement_ == address(0) || usdc_ == address(0)) {
            revert Unauthorized(address(0));
        }
        oracle = IPriceOracle(oracle_);
        settlement = ISettlement(settlement_);
        usdc = IERC20(usdc_);
        nextPositionId = 1;
    }

    // ─── openPosition ─────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function openPosition(
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        PriceBounds calldata bounds
    ) external override returns (uint256 positionId) {
        // ── Input validation ──────────────────────────────────────────────────
        if (collateral < MIN_COLLATERAL) revert InvalidCollateral(collateral);
        if (leverage == 0 || leverage > MAX_LEVERAGE) revert InvalidLeverage(leverage);
        if (block.timestamp > bounds.deadline) {
            revert DeadlineExpired(bounds.deadline, block.timestamp);
        }

        // ── Oracle validation ─────────────────────────────────────────────────
        (uint256 oraclePrice,) = oracle.getPrice();
        _checkPriceBounds(oraclePrice, bounds);

        // ── Record position ───────────────────────────────────────────────────
        positionId = nextPositionId++;
        _positions[positionId] = Position({
            trader: msg.sender,
            isLong: isLong,
            collateral: collateral,
            leverage: leverage,
            entryPrice: oraclePrice,
            timestamp: block.timestamp,
            isOpen: true
        });

        // ── Escrow collateral ─────────────────────────────────────────────────
        // Trader must have approved Settlement (not PerpEngine) for `collateral` USDC.
        settlement.depositCollateral(msg.sender, collateral);

        emit PositionOpened(positionId, msg.sender, isLong, collateral, leverage, oraclePrice);
    }

    // ─── closePosition ────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function closePosition(uint256 positionId, PriceBounds calldata bounds) external override {
        Position storage pos = _loadOpen(positionId);
        if (pos.trader != msg.sender) revert PositionNotFound(positionId);
        if (block.timestamp > bounds.deadline) {
            revert DeadlineExpired(bounds.deadline, block.timestamp);
        }

        // ── Oracle validation ─────────────────────────────────────────────────
        (uint256 exitPrice,) = oracle.getPrice();
        _checkPriceBounds(exitPrice, bounds);

        // ── PnL & payout ──────────────────────────────────────────────────────
        int256 pnl =
            _computePnl(pos.isLong, pos.collateral, pos.leverage, pos.entryPrice, exitPrice);
        uint256 payoutAmt = _boundedPayout(pos.collateral, pnl);

        pos.isOpen = false;

        if (payoutAmt > 0) {
            settlement.payout(pos.trader, payoutAmt);
        }

        emit PositionClosed(positionId, pos.trader, exitPrice, pnl);
    }

    // ─── liquidate ────────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function liquidate(uint256 positionId) external override {
        Position storage pos = _loadOpen(positionId);

        // ── Oracle (no caller-supplied bounds — protocol-determined) ──────────
        (uint256 liquidationPrice,) = oracle.getPrice();

        // ── Eligibility check ─────────────────────────────────────────────────
        if (!_isLiquidatable(pos, liquidationPrice)) {
            revert PositionHealthy(positionId);
        }

        // ── Compute equity and split payout ───────────────────────────────────
        int256 pnl = _computePnl(
            pos.isLong, pos.collateral, pos.leverage, pos.entryPrice, liquidationPrice
        );
        uint256 equity = _boundedPayout(pos.collateral, pnl);

        // Keeper reward capped to available equity.
        uint256 keeperReward = (pos.collateral * KEEPER_REWARD_BPS) / BPS_DENOM;
        if (keeperReward > equity) keeperReward = equity;
        uint256 traderPayout = equity - keeperReward;

        pos.isOpen = false;

        if (traderPayout > 0) settlement.payout(pos.trader, traderPayout);
        if (keeperReward > 0) settlement.payout(msg.sender, keeperReward);

        emit PositionLiquidated(positionId, pos.trader, liquidationPrice);
    }

    // ─── getPosition ──────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function getPosition(uint256 positionId) external view override returns (Position memory) {
        Position memory pos = _positions[positionId];
        if (pos.trader == address(0)) revert PositionNotFound(positionId);
        return pos;
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Load a position and revert if it is closed or doesn't exist.
    function _loadOpen(uint256 positionId) internal view returns (Position storage pos) {
        pos = _positions[positionId];
        if (pos.trader == address(0)) revert PositionNotFound(positionId);
        if (!pos.isOpen) revert PositionAlreadyClosed(positionId);
    }

    /// @dev Revert if oraclePrice falls outside [expected − maxDev, expected + maxDev].
    function _checkPriceBounds(uint256 oraclePrice, PriceBounds calldata bounds) internal pure {
        uint256 delta = oraclePrice > bounds.expectedPrice
            ? oraclePrice - bounds.expectedPrice
            : bounds.expectedPrice - oraclePrice;
        if (delta > bounds.maxDeviation) {
            revert PriceOutOfBounds(oraclePrice, bounds.expectedPrice, bounds.maxDeviation);
        }
    }

    /// @dev Compute signed PnL in USDC (6-decimal).
    ///
    ///      PnL = notional × (exitPrice − entryPrice) / entryPrice    (long)
    ///          = notional × (entryPrice − exitPrice) / entryPrice    (short)
    ///
    ///      Where notional = collateral × leverage.
    ///      Result is in 6-decimal USDC; prices are 8-decimal (1e8).
    ///      Division by entryPrice (8-decimal) cancels the scale factor.
    function _computePnl(
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        uint256 entryPrice,
        uint256 exitPrice
    ) internal pure returns (int256) {
        uint256 notional = collateral * leverage;
        if (isLong) {
            if (exitPrice >= entryPrice) {
                return int256(notional * (exitPrice - entryPrice) / entryPrice);
            } else {
                return -int256(notional * (entryPrice - exitPrice) / entryPrice);
            }
        } else {
            if (exitPrice <= entryPrice) {
                return int256(notional * (entryPrice - exitPrice) / entryPrice);
            } else {
                return -int256(notional * (exitPrice - entryPrice) / entryPrice);
            }
        }
    }

    /// @dev Convert (collateral, pnl) to a payout amount, floored at 0.
    ///      Guarantees the trader never loses more than their collateral.
    function _boundedPayout(uint256 collateral, int256 pnl) internal pure returns (uint256) {
        if (pnl >= 0) {
            return collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            return loss >= collateral ? 0 : collateral - loss;
        }
    }

    /// @dev True when a position's equity is below the maintenance margin threshold.
    ///      Equity = collateral + pnl (signed; floored at 0 is handled by Settlement).
    ///      Maintenance margin = notional × MAINTENANCE_MARGIN_BPS / BPS_DENOM.
    function _isLiquidatable(Position storage pos, uint256 currentPrice)
        internal
        view
        returns (bool)
    {
        uint256 notional = pos.collateral * pos.leverage;
        uint256 maintenanceMargin = (notional * MAINTENANCE_MARGIN_BPS) / BPS_DENOM;
        int256 pnl =
            _computePnl(pos.isLong, pos.collateral, pos.leverage, pos.entryPrice, currentPrice);
        int256 equity = int256(pos.collateral) + pnl;
        return equity < int256(maintenanceMargin);
    }
}

// ─── Extra error (not in IPerpEngine) ────────────────────────────────────────

/// @notice Thrown when liquidate() is called on a position above maintenance margin.
error PositionHealthy(uint256 positionId);
