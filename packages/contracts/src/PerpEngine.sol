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

    /// @notice Maximum leverage that does not create a position immediately liquidatable at entry.
    ///         At entry equity = collateral; maintenanceMargin = collateral × leverage × 5%.
    ///         Not immediately liquidatable iff: leverage ≤ 10_000 / MAINTENANCE_MARGIN_BPS = 20.
    uint256 public constant MAX_SAFE_LEVERAGE = 10_000 / MAINTENANCE_MARGIN_BPS;

    uint256 private constant BPS_DENOM = 10_000;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice Oracle that provides TWAP-validated prices.
    IPriceOracle public immutable oracle;

    /// @notice Settlement escrow that holds all USDC.
    ISettlement public immutable settlement;

    /// @notice USDC token address (used only for ABI exposure / off-chain approval).
    IERC20 public immutable usdc;

    // ─── Packed storage ──────────────────────────────────────────────────────

    /// @dev Internal packed layout — 2 storage slots instead of 6.
    ///
    ///      Slot 0 (32 bytes):
    ///        address trader   (20B) + uint8 leverage (1B) + uint40 timestamp (5B)
    ///        + bool isLong (1B) + bool isOpen (1B) = 28 bytes
    ///
    ///      Slot 1 (32 bytes):
    ///        uint128 collateral (16B) + uint128 entryPrice (16B) = 32 bytes
    ///
    ///      Safe ranges:
    ///        leverage  → uint8 max 255 (MAX_SAFE_LEVERAGE=20, well within)
    ///        timestamp → uint40 max 1_099_511_627_775 (year ~36812)
    ///        collateral→ uint128 max ~3.4×10^38 (>> any realistic USDC amount at 6 decimals)
    ///        entryPrice→ uint128 max ~3.4×10^38 (>> any realistic price at 8 decimals)
    struct PackedPosition {
        // Slot 0
        address trader;
        uint8 leverage;
        uint40 timestamp;
        bool isLong;
        bool isOpen;
        // Slot 1
        uint128 collateral;
        uint128 entryPrice;
    }

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Next position ID to assign. Starts at 1.
    uint256 public nextPositionId;

    /// @dev positionId → PackedPosition (2 storage slots instead of 6).
    mapping(uint256 => PackedPosition) private _packed;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param oracle_     PriceOracle address.
    /// @param settlement_ Settlement escrow address.
    /// @param usdc_       MockUSDC (or production USDC) token address.
    constructor(address oracle_, address settlement_, address usdc_) {
        if (oracle_ == address(0) || settlement_ == address(0) || usdc_ == address(0)) {
            revert ZeroAddress();
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
        // Absolute cap first.
        if (leverage == 0 || leverage > MAX_LEVERAGE) revert InvalidLeverage(leverage);
        // Safety bound: positions must not be immediately liquidatable at the entry price.
        // At entry equity = collateral; maintenanceMargin = collateral × leverage × 5% / 100%.
        // Not immediately liquidatable iff leverage × MAINTENANCE_MARGIN_BPS ≤ BPS_DENOM.
        if (leverage * MAINTENANCE_MARGIN_BPS > BPS_DENOM) revert InvalidLeverage(leverage);
        if (block.timestamp > bounds.deadline) {
            revert DeadlineExpired(bounds.deadline, block.timestamp);
        }

        // ── Oracle validation ─────────────────────────────────────────────────
        // slither-disable-next-line unused-return
        (uint256 oraclePrice,) = oracle.getPrice();
        _checkPriceBounds(oraclePrice, bounds);

        // ── Record position (packed into 2 storage slots) ─────────────────────
        // Safe narrowing casts — revert instead of silent truncation.
        if (collateral > type(uint128).max) revert SafeCastOverflow();
        if (oraclePrice > type(uint128).max) revert SafeCastOverflow();
        if (block.timestamp > type(uint40).max) revert SafeCastOverflow();
        // leverage is validated above (≤ MAX_SAFE_LEVERAGE = 20, fits uint8).

        positionId = nextPositionId++;
        _packed[positionId] = PackedPosition({
            trader: msg.sender,
            leverage: uint8(leverage),
            timestamp: uint40(block.timestamp),
            isLong: isLong,
            isOpen: true,
            collateral: uint128(collateral),
            entryPrice: uint128(oraclePrice)
        });

        // ── Escrow collateral ─────────────────────────────────────────────────
        // Trader must have approved Settlement (not PerpEngine) for `collateral` USDC.
        settlement.depositCollateral(msg.sender, collateral);

        emit PositionOpened(positionId, msg.sender, isLong, collateral, leverage, oraclePrice);
    }

    // ─── closePosition ────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function closePosition(uint256 positionId, PriceBounds calldata bounds) external override {
        PackedPosition storage pp = _loadOpenPacked(positionId);
        if (pp.trader != msg.sender) revert PositionNotFound(positionId);
        if (block.timestamp > bounds.deadline) {
            revert DeadlineExpired(bounds.deadline, block.timestamp);
        }

        // ── Oracle validation ─────────────────────────────────────────────────
        // slither-disable-next-line unused-return
        (uint256 exitPrice,) = oracle.getPrice();
        _checkPriceBounds(exitPrice, bounds);

        // ── PnL & payout ──────────────────────────────────────────────────────
        uint256 col = pp.collateral;
        uint256 lev = pp.leverage;
        int256 pnl = _computePnl(pp.isLong, col, lev, pp.entryPrice, exitPrice);
        uint256 payoutAmt = _boundedPayout(col, pnl);

        pp.isOpen = false;

        if (payoutAmt > 0) {
            settlement.payout(pp.trader, payoutAmt);
        }

        emit PositionClosed(positionId, pp.trader, exitPrice, pnl);
    }

    // ─── liquidate ────────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function liquidate(uint256 positionId) external override {
        PackedPosition storage pp = _loadOpenPacked(positionId);

        // ── Oracle (no caller-supplied bounds — protocol-determined) ──────────
        // slither-disable-next-line unused-return
        (uint256 liquidationPrice,) = oracle.getPrice();

        // ── Eligibility check ─────────────────────────────────────────────────
        uint256 col = pp.collateral;
        uint256 lev = pp.leverage;
        if (!_isLiquidatable(pp.isLong, col, lev, pp.entryPrice, liquidationPrice)) {
            revert PositionHealthy(positionId);
        }

        // ── Compute equity and split payout ───────────────────────────────────
        int256 pnl = _computePnl(pp.isLong, col, lev, pp.entryPrice, liquidationPrice);
        uint256 equity = _boundedPayout(col, pnl);

        // Keeper reward capped to available equity.
        uint256 keeperReward = (col * KEEPER_REWARD_BPS) / BPS_DENOM;
        if (keeperReward > equity) keeperReward = equity;
        uint256 traderPayout = equity - keeperReward;

        pp.isOpen = false;

        if (traderPayout > 0) settlement.payout(pp.trader, traderPayout);
        if (keeperReward > 0) settlement.payout(msg.sender, keeperReward);

        emit PositionLiquidated(positionId, pp.trader, liquidationPrice);
    }

    // ─── getPosition ──────────────────────────────────────────────────────────

    /// @inheritdoc IPerpEngine
    function getPosition(uint256 positionId) external view override returns (Position memory) {
        PackedPosition storage pp = _packed[positionId];
        if (pp.trader == address(0)) revert PositionNotFound(positionId);
        return _unpack(pp);
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Load a packed position and revert if it is closed or doesn't exist.
    function _loadOpenPacked(uint256 positionId) internal view returns (PackedPosition storage pp) {
        pp = _packed[positionId];
        if (pp.trader == address(0)) revert PositionNotFound(positionId);
        if (!pp.isOpen) revert PositionAlreadyClosed(positionId);
    }

    /// @dev Unpack a PackedPosition into the ABI-compatible Position struct.
    function _unpack(PackedPosition storage pp) internal view returns (Position memory) {
        return Position({
            trader: pp.trader,
            isLong: pp.isLong,
            collateral: uint256(pp.collateral),
            leverage: uint256(pp.leverage),
            entryPrice: uint256(pp.entryPrice),
            timestamp: uint256(pp.timestamp),
            isOpen: pp.isOpen
        });
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
    function _isLiquidatable(
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        uint256 entryPrice,
        uint256 currentPrice
    ) internal pure returns (bool) {
        uint256 notional = collateral * leverage;
        uint256 maintenanceMargin = (notional * MAINTENANCE_MARGIN_BPS) / BPS_DENOM;
        int256 pnl = _computePnl(isLong, collateral, leverage, entryPrice, currentPrice);
        int256 equity = int256(collateral) + pnl;
        return equity < int256(maintenanceMargin);
    }
}

// ─── Extra errors (not in IPerpEngine) ───────────────────────────────────────

/// @notice Thrown when liquidate() is called on a position above maintenance margin.
error PositionHealthy(uint256 positionId);

/// @notice Thrown when address(0) is passed for a required constructor parameter.
///         Using a dedicated error (not Unauthorized) since this is parameter validation,
///         not an access-control failure.
error ZeroAddress();

/// @notice Thrown when a value overflows during narrowing cast to a packed storage type.
error SafeCastOverflow();
