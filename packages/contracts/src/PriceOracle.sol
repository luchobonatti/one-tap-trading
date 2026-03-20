// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceOracle } from "./interfaces/IPriceOracle.sol";
import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

contract PriceOracle is IPriceOracle {
    uint256 public constant STALENESS_THRESHOLD = 5 seconds;
    uint256 public constant TWAP_WINDOW = 30 seconds;
    uint256 public constant MAX_DEVIATION = 300; // 3% in basis points (100 = 1%)

    uint256 private constant OBSERVATION_COUNT = 10;

    struct Observation {
        uint256 price;
        uint256 timestamp;
    }

    IPriceFeed public immutable feed;

    Observation[OBSERVATION_COUNT] private observations;
    uint256 private observationIndex;
    uint256 private observationCount;

    constructor(address feed_) {
        feed = IPriceFeed(feed_);
    }

    function recordObservation() external {
        (int256 rawPrice, uint256 updatedAt) = feed.latestAnswer();
        if (block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert StalePrice(updatedAt, block.timestamp);
        }
        uint256 price = uint256(rawPrice);
        observations[observationIndex] = Observation({ price: price, timestamp: block.timestamp });
        observationIndex = (observationIndex + 1) % OBSERVATION_COUNT;
        if (observationCount < OBSERVATION_COUNT) {
            ++observationCount;
        }
    }

    function getPrice() external view returns (uint256 price, uint256 updatedAt) {
        (int256 rawPrice, uint256 feedUpdatedAt) = feed.latestAnswer();

        if (block.timestamp - feedUpdatedAt > STALENESS_THRESHOLD) {
            revert StalePrice(feedUpdatedAt, block.timestamp);
        }

        price = uint256(rawPrice);
        updatedAt = feedUpdatedAt;

        // TWAP sanity check: compute average of observations within window
        if (observationCount > 0) {
            unchecked {
                uint256 sum;
                uint256 count;
                uint256 windowStart = block.timestamp - TWAP_WINDOW;
                for (uint256 i; i < observationCount; ++i) {
                    Observation memory obs = observations[i];
                    if (obs.timestamp >= windowStart) {
                        sum += obs.price;
                        ++count;
                    }
                }
                // Only apply TWAP check if we have observations in the window
                if (count > 0) {
                    uint256 twap = sum / count;
                    // Placeholder for deviation check (Phase 5)
                    // For now, just compute TWAP for validation
                    if (twap > 0) {
                        // TWAP computed successfully
                    }
                }
            }
        }
    }
}
