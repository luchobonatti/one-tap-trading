// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPerpEngine
/// @notice Interface for the One Tap Trading perpetual futures engine
interface IPerpEngine {
    struct Position {
        address trader;
        bool isLong;
        uint256 collateral;
        uint256 leverage;
        uint256 entryPrice;
        uint256 timestamp;
        bool isOpen;
    }

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

    function openPosition(bool isLong, uint256 collateral, uint256 leverage)
        external
        returns (uint256 positionId);

    function closePosition(uint256 positionId) external;

    function liquidate(uint256 positionId) external;

    function getPosition(uint256 positionId) external view returns (Position memory);
}
