// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @title RedStoneAdapter
/// @notice Adapts a RedStone Bolt AggregatorV3 feed to our IPriceFeed interface.
///
///         RedStone Bolt reports timestamps in microseconds (MegaETH block.timestamp is
///         in seconds), so updatedAt is divided by 1_000_000 before returning.
///
///         Feed address on Carrot testnet (chain 6343): 0x9674Dbe42f9996e1470F8eC15a6D0aebA4a93AEb
contract RedStoneAdapter is IPriceFeed {
    IAggregatorV3 public immutable feed;

    constructor(address _feed) {
        feed = IAggregatorV3(_feed);
    }

    function latestAnswer() external view override returns (int256 price, uint256 updatedAt) {
        uint256 updatedAtNs;
        (, price,, updatedAtNs,) = feed.latestRoundData();
        updatedAt = updatedAtNs / 1_000_000;
    }
}
