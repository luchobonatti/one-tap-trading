// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPriceOracle {
    error StalePrice(uint256 updatedAt, uint256 currentTime);
    error InsufficientObservations();

    function getPrice() external view returns (uint256 price, uint256 updatedAt);
}
