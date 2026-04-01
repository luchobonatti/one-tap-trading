// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title ISessionKeyValidator
/// @notice Interface for session key validation in One Tap Trading.
///         Enforces ephemeral key permissions for PerpEngine operations.
interface ISessionKeyValidator {
    // ─── Structs ──────────────────────────────────────────────────────────────

    /// @notice Session key authorization data.
    /// @param sessionKey The ephemeral ECDSA key authorized to sign operations.
    /// @param validUntil Expiration timestamp (unix seconds). Session invalid if block.timestamp > validUntil.
    /// @param targetContract The only contract this session key can call (must be PerpEngine).
    /// @param allowedSelectors Array of function selectors this key can invoke.
    /// @param spendLimit Maximum cumulative USDC (6 decimals) this key can spend across all openPosition calls.
    /// @param spentAmount Accumulated USDC spent so far (updated on each openPosition).
    /// @param active Whether this session is currently active (false = revoked).
    struct SessionData {
        address sessionKey;
        uint48 validUntil;
        address targetContract;
        bytes4[] allowedSelectors;
        uint256 spendLimit;
        uint256 spentAmount;
        bool active;
    }

    // ─── Events ───────────────────────────────────────────────────────────────

    /// @notice Emitted when a session key is granted.
    event SessionGranted(
        address indexed owner,
        address indexed sessionKey,
        uint48 validUntil,
        address targetContract,
        uint256 spendLimit
    );

    /// @notice Emitted when a session key is revoked.
    event SessionRevoked(address indexed owner);

    // ─── Custom errors ────────────────────────────────────────────────────────

    /// @notice Thrown when the session has expired.
    error SessionExpired(uint48 validUntil, uint48 blockTimestamp);

    /// @notice Thrown when the session is not active (revoked).
    error SessionNotActive();

    /// @notice Thrown when the target contract is not allowed.
    error TargetNotAllowed(address target, address allowedTarget);

    /// @notice Thrown when the function selector is not allowed.
    error SelectorNotAllowed(bytes4 selector);

    /// @notice Thrown when the spend limit would be exceeded.
    error SpendLimitExceeded(uint256 spent, uint256 limit);

    /// @notice Thrown when a session is already granted for this owner.
    error SessionAlreadyGranted(address owner);

    /// @notice Thrown when an address parameter is zero.
    error ZeroAddress();

    /// @notice Thrown when the session key does not match the signer.
    error InvalidSessionKey(address expected, address actual);

    // ─── Core functions ───────────────────────────────────────────────────────

    /// @notice Grant a session key to the caller.
    /// @param sessionKey The ephemeral ECDSA key to authorize.
    /// @param validUntil Expiration timestamp (unix seconds).
    /// @param targetContract The contract this key can call (must be PerpEngine).
    /// @param allowedSelectors Array of function selectors this key can invoke.
    /// @param spendLimit Maximum cumulative USDC (6 decimals) this key can spend.
    /// @dev Reverts if a session is already active for msg.sender.
    /// @dev Reverts if sessionKey or targetContract is address(0).
    function grantSession(
        address sessionKey,
        uint48 validUntil,
        address targetContract,
        bytes4[] calldata allowedSelectors,
        uint256 spendLimit
    ) external;

    /// @notice Revoke the active session for the caller.
    /// @dev Sets active = false. Does not delete the session data.
    function revokeSession() external;

    /// @notice Get the session data for an owner.
    /// @param owner The account that owns the session.
    /// @return The SessionData struct (may have active = false if revoked).
    function getSession(address owner) external view returns (SessionData memory);

    // ─── ERC-7579 Validator Interface ─────────────────────────────────────────

    /// @notice Validate a UserOperation using session key authorization.
    /// @param userOp The packed user operation.
    /// @param userOpHash The hash of the user operation (signed by the session key).
    /// @return 0 if validation succeeds, 1 if it fails.
    /// @dev NEVER reverts. Returns 0 (success) or 1 (failure).
    /// @dev Extracts sessionKey from userOp.signature[21:41] (after 1-byte mode + 20-byte validatorAddr).
    /// @dev Verifies ECDSA signature, session validity, target, selector, and spend limits.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        returns (uint256);

    /// @notice Validate a signature for offchain use (ERC-1271 style).
    /// @param sender The account that owns the session.
    /// @param hash The hash being signed.
    /// @param signature The signature bytes (sessionKey || ecdsaSig).
    /// @return The ERC-1271 magic value (0x1626ba7e) if valid, 0xffffffff otherwise.
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);

    /// @notice Called when this module is installed on an account.
    /// @param data Optional initialization data (unused in this implementation).
    function onInstall(bytes calldata data) external;

    /// @notice Called when this module is uninstalled from an account.
    /// @param data Optional uninstallation data (unused in this implementation).
    function onUninstall(bytes calldata data) external;

    /// @notice Check if this contract implements a given module type.
    /// @param moduleTypeId The module type ID (1 = validator).
    /// @return True if this contract implements the module type.
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
}
