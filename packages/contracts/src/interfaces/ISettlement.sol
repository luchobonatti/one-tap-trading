// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISettlement
/// @notice Escrow and solvency accounting for One Tap Trading collateral.
///         All USDC flows through this contract — PerpEngine never holds funds.
interface ISettlement {
    // ─── Events ──────────────────────────────────────────────────────────────

    /// @notice Emitted when a trader's collateral is escrowed.
    event CollateralDeposited(address indexed trader, uint256 amount);

    /// @notice Emitted when funds are released to a recipient.
    event PayoutExecuted(address indexed recipient, uint256 amount);

    /// @notice Emitted when the owner tops up the house reserve.
    event HouseReserveFunded(address indexed funder, uint256 amount);

    /// @notice Emitted when the authorised engine address is updated.
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);

    // ─── Custom errors ────────────────────────────────────────────────────────

    /// @notice Thrown when a restricted function is called by an unauthorised address.
    error Unauthorized(address caller);

    /// @notice Thrown when a payout would violate the solvency invariant.
    ///         `available` = totalCollateral + houseReserve − totalPayouts.
    error SolvencyViolation(uint256 requested, uint256 available);

    /// @notice Thrown when address(0) is passed for a required address parameter.
    error ZeroAddress();

    /// @notice Thrown when a zero amount is supplied where a positive value is required.
    error ZeroAmount();

    // ─── Engine-only functions ────────────────────────────────────────────────

    /// @notice Pull `amount` USDC from `trader` into escrow.
    ///         Requires `trader` to have approved this contract for at least `amount`.
    /// @dev    Only callable by the authorised engine.
    function depositCollateral(address trader, uint256 amount) external;

    /// @notice Send `amount` USDC to `recipient` and update accounting.
    ///         Reverts with SolvencyViolation if the invariant would be broken.
    /// @dev    Only callable by the authorised engine.
    function payout(address recipient, uint256 amount) external;

    // ─── Owner-only functions ─────────────────────────────────────────────────

    /// @notice Transfer `amount` USDC from the owner into the house reserve.
    ///         Requires the owner to have approved this contract for at least `amount`.
    function fundHouseReserve(uint256 amount) external;

    /// @notice Replace the authorised engine address.
    /// @dev    Use with care — the old engine's in-flight positions will break.
    function setEngine(address newEngine) external;

    // ─── View functions ───────────────────────────────────────────────────────

    /// @notice USDC token contract address.
    function usdc() external view returns (address);

    /// @notice Currently authorised engine address.
    function engine() external view returns (address);

    /// @notice Cumulative USDC deposited as collateral (monotonically increasing).
    function totalCollateral() external view returns (uint256);

    /// @notice Cumulative USDC funded by the owner into the house reserve.
    function houseReserve() external view returns (uint256);

    /// @notice Cumulative USDC paid out via payout() (monotonically increasing).
    function totalPayouts() external view returns (uint256);

    /// @notice Remaining USDC that can be paid out before the solvency invariant breaks.
    ///         = totalCollateral + houseReserve − totalPayouts
    function solvencyBuffer() external view returns (uint256);
}
