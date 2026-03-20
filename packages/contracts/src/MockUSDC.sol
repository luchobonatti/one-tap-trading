// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Minimal USDC-like ERC-20 for testnet. 6 decimals, public faucet, no access control.
contract MockUSDC is ERC20 {
    /// @notice Maximum tokens mintable per faucet call (10 000 USDC).
    uint256 public constant FAUCET_AMOUNT = 10_000e6;

    /// @notice Thrown when `amount` exceeds the per-call faucet cap.
    error FaucetAmountExceedsLimit(uint256 amount, uint256 limit);

    constructor() ERC20("Mock USD Coin", "USDC") { }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint `amount` tokens to the caller. Capped at FAUCET_AMOUNT per call.
    /// @param amount Amount in 6-decimal units to mint to msg.sender.
    function faucet(uint256 amount) external {
        if (amount > FAUCET_AMOUNT) revert FaucetAmountExceedsLimit(amount, FAUCET_AMOUNT);
        _mint(msg.sender, amount);
    }

    /// @dev Test helper — any address can mint any amount to any recipient. Testnet only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
