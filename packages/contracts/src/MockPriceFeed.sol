// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceFeed } from "./interfaces/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    int256 private _price;
    uint256 private _updatedAt;
    bool private _forceUpdatedAt;

    constructor(int256 initialPrice) {
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
        _forceUpdatedAt = false;
    }

    /// @dev Calling this freezes the reported timestamp so tests can exercise
    ///      staleness checks. Cleared by setPrice().
    function setUpdatedAt(uint256 updatedAt) external {
        _updatedAt = updatedAt;
        _forceUpdatedAt = true;
    }

    function latestAnswer() external view returns (int256 price, uint256 updatedAt) {
        return (_price, _forceUpdatedAt ? _updatedAt : block.timestamp);
    }
}
