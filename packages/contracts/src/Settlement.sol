// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISettlement } from "./interfaces/ISettlement.sol";

/// @title Settlement
/// @notice Escrow contract that custodies all USDC collateral and enforces the core
///         protocol solvency invariant: cumulative payouts ≤ cumulative deposits + house reserve.
///
///         Only the authorised PerpEngine may deposit collateral or execute payouts.
///         The owner funds the house reserve to cover trader profits.
contract Settlement is ISettlement, Ownable {
    using SafeERC20 for IERC20;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @inheritdoc ISettlement
    address public immutable override usdc;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @inheritdoc ISettlement
    address public override engine;

    /// @inheritdoc ISettlement
    uint256 public override totalCollateral;

    /// @inheritdoc ISettlement
    uint256 public override houseReserve;

    /// @inheritdoc ISettlement
    uint256 public override totalPayouts;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param usdc_   Address of the USDC ERC-20 token (MockUSDC on testnet).
    /// @param engine_ Authorised PerpEngine address. May be address(0) to allow deploying
    ///                Settlement before PerpEngine (two-step setup via setEngine).
    ///                All engine-only calls revert with Unauthorized until the engine is set.
    constructor(address usdc_, address engine_) Ownable(msg.sender) {
        if (usdc_ == address(0)) revert ZeroAddress();
        usdc = usdc_;
        engine = engine_;
    }

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyEngine() {
        if (msg.sender != engine) revert Unauthorized(msg.sender);
        _;
    }

    // ─── Engine-only ──────────────────────────────────────────────────────────

    /// @inheritdoc ISettlement
    /// @dev Pulls USDC from `trader` directly — the trader must have approved this
    ///      contract for at least `amount` before the engine calls this function.
    ///      Assumes standard ERC-20 transfer semantics (no fee-on-transfer). If a
    ///      fee-on-transfer token is ever used, totalCollateral may overstate actual balance.
    function depositCollateral(address trader, uint256 amount) external override onlyEngine {
        if (amount == 0) revert ZeroAmount();
        totalCollateral += amount;
        IERC20(usdc).safeTransferFrom(trader, address(this), amount);
        emit CollateralDeposited(trader, amount);
    }

    /// @inheritdoc ISettlement
    function payout(address recipient, uint256 amount) external override onlyEngine {
        if (amount == 0) revert ZeroAmount();
        uint256 buffer = solvencyBuffer();
        if (amount > buffer) revert SolvencyViolation(amount, buffer);
        totalPayouts += amount;
        IERC20(usdc).safeTransfer(recipient, amount);
        emit PayoutExecuted(recipient, amount);
    }

    // ─── Owner-only ───────────────────────────────────────────────────────────

    /// @inheritdoc ISettlement
    /// @dev Assumes standard ERC-20 transfer semantics (no fee-on-transfer).
    function fundHouseReserve(uint256 amount) external override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        houseReserve += amount;
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        emit HouseReserveFunded(msg.sender, amount);
    }

    /// @inheritdoc ISettlement
    function setEngine(address newEngine) external override onlyOwner {
        if (newEngine == address(0)) revert ZeroAddress();
        address old = engine;
        engine = newEngine;
        emit EngineUpdated(old, newEngine);
    }

    /// @notice Recover ERC-20 tokens sent directly to this contract outside normal flows.
    /// @dev    Intended for tokens accidentally transferred, or for USDC provably in excess
    ///         of the solvency buffer. Recovering tracked USDC will desync internal accounting —
    ///         only call this for tokens that entered via direct transfer, never via
    ///         depositCollateral or fundHouseReserve.
    /// @param token  ERC-20 token to recover.
    /// @param amount Amount to send to the owner.
    function recover(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @inheritdoc ISettlement
    function solvencyBuffer() public view override returns (uint256) {
        uint256 total = totalCollateral + houseReserve;
        // totalPayouts is always ≤ total by invariant, so no underflow possible.
        return total - totalPayouts;
    }
}
