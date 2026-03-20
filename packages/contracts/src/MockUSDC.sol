// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 10_000e6; // 10,000 USDC per call

    constructor() ERC20("Mock USD Coin", "USDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
