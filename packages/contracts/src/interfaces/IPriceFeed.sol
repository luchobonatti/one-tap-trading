// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPriceFeed
/// @notice Minimal adapter interface for price feeds (MockPriceFeed in tests, RedStone Bolt in production).
interface IPriceFeed {
    /// @notice Return the latest price and the timestamp of that update.
    /// @return price     Raw price in 8-decimal units (1e8 = $1.00), as a signed integer.
    ///                   Consumers MUST reject non-positive values (zero or negative are invalid).
    /// @return updatedAt Unix timestamp (seconds) when the feed last produced this price.
    function latestAnswer() external view returns (int256 price, uint256 updatedAt);
}
