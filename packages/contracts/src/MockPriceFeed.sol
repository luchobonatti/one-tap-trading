// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    int256 private _price;
    uint256 private _updatedAt;

    constructor(int256 initialPrice) {
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 updatedAt) external {
        _updatedAt = updatedAt;
    }

    function latestAnswer() external view returns (int256 price, uint256 updatedAt) {
        return (_price, block.timestamp);
    }
}
