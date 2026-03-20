// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPerpEngine
/// @notice Interface for the One Tap Trading perpetual futures engine.
///         Functions accept off-chain price bounds so the contract can reject
///         stale or manipulated execution prices at the protocol level.
interface IPerpEngine {
    // ─── Structs ─────────────────────────────────────────────────────────────

    /// @notice Full on-chain state for a single position.
    struct Position {
        address trader;
        bool isLong;
        uint256 collateral; // 6-decimal USDC units
        uint256 leverage; // integer multiplier (e.g. 10 = 10×)
        uint256 entryPrice; // 8-decimal oracle price at open
        uint256 timestamp; // block.timestamp at open
        bool isOpen;
    }

    /// @notice Caller-supplied bounds that gate all price-sensitive operations.
    ///         The engine reverts if the oracle price falls outside
    ///         [expectedPrice - maxDeviation, expectedPrice + maxDeviation]
    ///         or if block.timestamp > deadline.
    struct PriceBounds {
        uint256 expectedPrice; // 8-decimal mid-price the caller observed off-chain
        uint256 maxDeviation; // max tolerated absolute deviation (8-decimal units)
        uint256 deadline; // unix timestamp after which the tx is rejected
    }

    // ─── Events ──────────────────────────────────────────────────────────────

    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        uint256 entryPrice
    );

    event PositionClosed(
        uint256 indexed positionId, address indexed trader, uint256 exitPrice, int256 pnl
    );

    event PositionLiquidated(
        uint256 indexed positionId, address indexed trader, uint256 liquidationPrice
    );

    // ─── Custom errors ───────────────────────────────────────────────────────

    /// @notice Thrown when the oracle price deviates beyond the caller's bounds.
    error PriceOutOfBounds(uint256 oraclePrice, uint256 expectedPrice, uint256 maxDeviation);

    /// @notice Thrown when block.timestamp has passed the caller's deadline.
    error DeadlineExpired(uint256 deadline, uint256 blockTimestamp);

    /// @notice Thrown when the position does not exist or does not belong to the caller.
    error PositionNotFound(uint256 positionId);

    /// @notice Thrown when an operation is attempted on a position that is already closed.
    error PositionAlreadyClosed(uint256 positionId);

    /// @notice Thrown when collateral is zero or below the minimum.
    error InvalidCollateral(uint256 collateral);

    /// @notice Thrown when leverage is zero or above the maximum allowed.
    error InvalidLeverage(uint256 leverage);

    /// @notice Thrown when the caller is not authorised for the given operation.
    error Unauthorized(address caller);

    // ─── Core functions ──────────────────────────────────────────────────────

    /// @notice Open a leveraged position.
    /// @param isLong   Direction: true = long, false = short.
    /// @param collateral Amount of collateral (6-decimal USDC) to deposit.
    /// @param leverage  Integer leverage multiplier (e.g. 10 = 10×).
    /// @param bounds   Off-chain price bounds; reverts if oracle is outside range or past deadline.
    /// @return positionId Unique identifier for the new position.
    function openPosition(
        bool isLong,
        uint256 collateral,
        uint256 leverage,
        PriceBounds calldata bounds
    ) external returns (uint256 positionId);

    /// @notice Close an open position at the current oracle price.
    /// @param positionId Position to close.
    /// @param bounds     Off-chain price bounds for exit price validation.
    function closePosition(uint256 positionId, PriceBounds calldata bounds) external;

    /// @notice Liquidate an under-margined position.
    /// @param positionId Position to liquidate.
    /// @param bounds     Off-chain price bounds used to verify liquidation is valid.
    function liquidate(uint256 positionId, PriceBounds calldata bounds) external;

    /// @notice Return the full state of a position.
    /// @param positionId Position identifier.
    function getPosition(uint256 positionId) external view returns (Position memory);
}
