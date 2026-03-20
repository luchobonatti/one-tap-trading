// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDC
/// @notice Minimal USDC-like ERC-20 for testnet collateral.
///         6 decimals, public rate-limited faucet, owner-only mint for test setup.
contract MockUSDC is ERC20, Ownable {
    /// @notice Maximum tokens mintable per faucet call (10 000 USDC).
    uint256 public constant FAUCET_AMOUNT = 10_000e6;

    /// @notice Thrown when `amount` exceeds the per-call faucet cap.
    error FaucetAmountExceedsLimit(uint256 amount, uint256 limit);

    constructor() ERC20("Mock USD Coin", "USDC") Ownable(msg.sender) { }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint `amount` tokens to the caller. Capped at FAUCET_AMOUNT per call.
    ///         No authentication — intended for public testnet onboarding.
    /// @param amount Amount in 6-decimal units to mint to msg.sender.
    function faucet(uint256 amount) external {
        if (amount > FAUCET_AMOUNT) revert FaucetAmountExceedsLimit(amount, FAUCET_AMOUNT);
        _mint(msg.sender, amount);
    }

    /// @notice Mint arbitrary tokens to any recipient. Owner-only test setup helper.
    /// @dev    Restricted to the deployer so collateral accounting in integration tests
    ///         is not trivially inflatable by untrusted accounts on shared testnets.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
