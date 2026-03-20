// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceOracle {
    /// @notice Thrown when the feed's last update is older than STALENESS_THRESHOLD.
    error StalePrice(uint256 updatedAt, uint256 currentTime);

    /// @notice Thrown when observations exist but none fall within the TWAP window.
    ///         Indicates the keeper has stopped recording prices; fail safe.
    error InsufficientObservations();

    /// @notice Thrown when the feed returns a zero or negative raw price.
    error InvalidPrice(int256 rawPrice);

    /// @notice Thrown when the constructor receives the zero address.
    error ZeroAddress();

    /// @notice Thrown when spot price deviates from TWAP beyond MAX_DEVIATION.
    error PriceDeviationExceedsMax(uint256 spotPrice, uint256 twapPrice, uint256 deviationBps);

    /// @notice Return the current validated price and its feed timestamp.
    /// @dev Reverts with StalePrice, InsufficientObservations, InvalidPrice, or
    ///      PriceDeviationExceedsMax on unhealthy oracle state.
    function getPrice() external view returns (uint256 price, uint256 updatedAt);
}
