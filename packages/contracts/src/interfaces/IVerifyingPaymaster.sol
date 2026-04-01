// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IVerifyingPaymaster
/// @notice Paymaster that sponsors gas for trading UserOperations targeting PerpEngine
///         and delegation UserOperations (USDC approve + session key grant).
///         Validates that UserOps call allowed functions before sponsoring gas.
interface IVerifyingPaymaster {
    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when gas is sponsored for a UserOperation.
    /// @param sender The account that initiated the UserOperation.
    /// @param actualGasCost The actual gas cost paid by the paymaster.
    event GasSponsored(address indexed sender, uint256 actualGasCost);

    /// @notice Emitted when the allowed target (PerpEngine) address is updated.
    /// @param oldTarget The previous allowed target address.
    /// @param newTarget The new allowed target address.
    event AllowedTargetUpdated(address indexed oldTarget, address indexed newTarget);

    /// @notice Emitted when the MockUSDC address is updated.
    /// @param oldMockUsdc The previous MockUSDC address.
    /// @param newMockUsdc The new MockUSDC address.
    event MockUsdcUpdated(address indexed oldMockUsdc, address indexed newMockUsdc);

    /// @notice Emitted when the SessionKeyValidator address is updated.
    /// @param oldValidator The previous SessionKeyValidator address.
    /// @param newValidator The new SessionKeyValidator address.
    event SessionKeyValidatorUpdated(address indexed oldValidator, address indexed newValidator);

    /// @notice Emitted when the approve spender (Settlement) address is updated.
    /// @param oldSpender The previous approve spender address.
    /// @param newSpender The new approve spender address.
    event ApproveSpenderUpdated(address indexed oldSpender, address indexed newSpender);

    /// @notice Emitted when the gas allowance per operation is updated.
    /// @param oldAllowance The previous gas allowance per operation.
    /// @param newAllowance The new gas allowance per operation.
    event GasAllowanceUpdated(uint256 oldAllowance, uint256 newAllowance);

    // ─── Custom errors ────────────────────────────────────────────────────────

    /// @notice Thrown when a UserOperation targets an address other than the allowed targets.
    /// @param target The target address that was not allowed.
    error TargetNotAllowed(address target);

    /// @notice Thrown when a UserOperation calls a function selector that is not allowed.
    /// @param selector The function selector that was not allowed.
    error SelectorNotAllowed(bytes4 selector);

    /// @notice Thrown when the gas cost exceeds the per-operation allowance.
    /// @param maxCost The maximum cost requested.
    /// @param allowance The per-operation gas allowance.
    error GasAllowanceExceeded(uint256 maxCost, uint256 allowance);

    /// @notice Thrown when address(0) is passed for a required address parameter.
    error ZeroAddress();

    /// @notice Thrown when a function is called by an address other than the EntryPoint.
    /// @param caller The address that called the function.
    error NotEntryPoint(address caller);

    // ─── Owner-only functions ─────────────────────────────────────────────────

    /// @notice Update the allowed trading target address (PerpEngine).
    /// @param newTarget The new allowed target address.
    /// @dev Only callable by the owner.
    function setAllowedTarget(address newTarget) external;

    /// @notice Update the MockUSDC address.
    /// @param newMockUsdc The new MockUSDC address.
    /// @dev Only callable by the owner.
    function setMockUsdc(address newMockUsdc) external;

    /// @notice Update the SessionKeyValidator address.
    /// @param newValidator The new SessionKeyValidator address.
    /// @dev Only callable by the owner.
    function setSessionKeyValidator(address newValidator) external;

    /// @notice Update the approve spender address (Settlement).
    /// @param newSpender The new approve spender address.
    /// @dev Only callable by the owner.
    function setApproveSpender(address newSpender) external;

    /// @notice Update the maximum gas allowance per UserOperation.
    /// @param newAllowance The new gas allowance per operation.
    /// @dev Only callable by the owner.
    function setGasAllowancePerOp(uint256 newAllowance) external;

    // ─── Deposit management ────────────────────────────────────────────────────

    /// @notice Deposit ETH to the EntryPoint to fund gas sponsorship.
    /// @dev Payable function that forwards the received ETH to the EntryPoint.
    function deposit() external payable;

    /// @notice Withdraw ETH from the EntryPoint deposit.
    /// @param amount The amount to withdraw.
    /// @dev Only callable by the owner.
    function withdraw(uint256 amount) external;

    /// @notice Get the current deposit balance in the EntryPoint.
    /// @return The current deposit balance.
    function getDeposit() external view returns (uint256);
}
