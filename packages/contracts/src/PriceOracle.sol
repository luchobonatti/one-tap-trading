// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

contract PriceOracle is IPriceOracle {
    /// @notice Maximum age of a feed update before it is considered stale (seconds).
    uint256 public constant STALENESS_THRESHOLD = 5 seconds;

    /// @notice Width of the TWAP observation window (seconds).
    uint256 public constant TWAP_WINDOW = 30 seconds;

    /// @notice Maximum allowed deviation between spot and TWAP, in basis points (300 = 3%).
    uint256 public constant MAX_DEVIATION = 300;

    uint256 private constant OBSERVATION_COUNT = 10;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    /// @notice Pluggable price feed (MockPriceFeed in tests, RedStone Bolt in production).
    IPriceFeed public immutable feed;

    Observation[OBSERVATION_COUNT] private observations;
    uint256 private observationIndex;
    uint256 private observationCount;

    constructor(address feed_) {
        if (feed_ == address(0)) revert ZeroAddress();
        feed = IPriceFeed(feed_);
    }

    /// @notice Record the current feed price as a TWAP observation.
    /// @dev    Permissionless — any caller can push observations. Reverts on stale or
    ///         invalid feed data so bad prices are never written to the ring buffer.
    function recordObservation() external {
        (int256 rawPrice, uint256 updatedAt) = feed.latestAnswer();
        if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert StalePrice(updatedAt, block.timestamp);
        }
        if (rawPrice <= 0) revert InvalidPrice(rawPrice);

        uint256 price = uint256(rawPrice);
        observations[observationIndex] = Observation({ price: price, timestamp: block.timestamp });
        observationIndex = (observationIndex + 1) % OBSERVATION_COUNT;
        if (observationCount < OBSERVATION_COUNT) {
            ++observationCount;
        }
    }

    /// @inheritdoc IPriceOracle
    function getPrice() external view returns (uint256 price, uint256 updatedAt) {
        (int256 rawPrice, uint256 feedUpdatedAt) = feed.latestAnswer();

        if (block.timestamp - feedUpdatedAt > STALENESS_THRESHOLD) {
            revert StalePrice(feedUpdatedAt, block.timestamp);
        }
        if (rawPrice <= 0) revert InvalidPrice(rawPrice);

        price = uint256(rawPrice);
        updatedAt = feedUpdatedAt;

        // TWAP sanity check: reject if spot deviates >MAX_DEVIATION from the 30s average.
        // Skipped on first use (observationCount == 0) to allow bootstrapping.
        if (observationCount > 0) {
            // windowStart computed outside unchecked to prevent silent underflow.
            uint256 windowStart = block.timestamp > TWAP_WINDOW ? block.timestamp - TWAP_WINDOW : 0;

            uint256 sum;
            uint256 count;
            for (uint256 i; i < observationCount; ++i) {
                Observation memory obs = observations[i];
                if (obs.timestamp >= windowStart) {
                    unchecked {
                        sum += obs.price;
                        ++count;
                    }
                }
            }

            // All observations are older than TWAP_WINDOW — the keeper has stopped;
            // fail safe rather than return a potentially stale TWAP-validated price.
            if (count == 0) revert InsufficientObservations();

            unchecked {
                uint256 twap = sum / count;
                uint256 deviation = price > twap ? price - twap : twap - price;
                uint256 deviationBps = deviation * BPS_DENOMINATOR / twap;
                if (deviationBps > MAX_DEVIATION) {
                    revert PriceDeviationExceedsMax(price, twap, deviationBps);
                }
            }
        }
    }
}
