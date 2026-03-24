// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ISessionKeyValidator } from "./interfaces/ISessionKeyValidator.sol";

/// @title SessionKeyValidator
/// @notice ERC-7579 validator module for session key authorization in One Tap Trading.
///         Enforces ephemeral ECDSA key permissions for PerpEngine operations.
contract SessionKeyValidator is ISessionKeyValidator {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice ERC-7579 module type ID for validators.
    uint256 private constant MODULE_TYPE_VALIDATOR = 1;

    /// @notice ERC-1271 magic value for valid signatures.
    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice ERC-1271 magic value for invalid signatures.
    bytes4 private constant ERC1271_INVALID = 0xffffffff;

    /// @notice Validation success return value.
    uint256 private constant VALIDATION_SUCCESS = 0;

    /// @notice Validation failure return value.
    uint256 private constant VALIDATION_FAILED = 1;

    /// @notice PerpEngine openPosition function selector.
    bytes4 private constant OPEN_POSITION_SELECTOR = 0x5a6c3d4a;

    /// @notice PerpEngine closePosition function selector.
    bytes4 private constant CLOSE_POSITION_SELECTOR = 0x5c36b186;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice Mapping of account owner to their session data.
    mapping(address owner => SessionData) public sessions;

    // ─── Constructor ───────────────────────────────────────────────────────────

    constructor() { }

    // ─── Core functions ───────────────────────────────────────────────────────

    /// @inheritdoc ISessionKeyValidator
    function grantSession(
        address sessionKey,
        uint48 validUntil,
        address targetContract,
        bytes4[] calldata allowedSelectors,
        uint256 spendLimit
    ) external {
        if (sessionKey == address(0)) revert ZeroAddress();
        if (targetContract == address(0)) revert ZeroAddress();
        if (sessions[msg.sender].active) revert SessionAlreadyGranted(msg.sender);

        sessions[msg.sender] = SessionData({
            sessionKey: sessionKey,
            validUntil: validUntil,
            targetContract: targetContract,
            allowedSelectors: allowedSelectors,
            spendLimit: spendLimit,
            spentAmount: 0,
            active: true
        });

        emit SessionGranted(msg.sender, sessionKey, validUntil, targetContract, spendLimit);
    }

    /// @inheritdoc ISessionKeyValidator
    function revokeSession() external {
        sessions[msg.sender].active = false;
        emit SessionRevoked(msg.sender);
    }

    /// @inheritdoc ISessionKeyValidator
    function getSession(address owner) external view returns (SessionData memory) {
        return sessions[owner];
    }

    // ─── ERC-7579 Validator Interface ─────────────────────────────────────────

    /// @inheritdoc ISessionKeyValidator
    function validateUserOp(bytes calldata userOp, bytes32 userOpHash) external returns (uint256) {
        // Decode PackedUserOperation
        address sender;
        bytes memory callData;
        bytes memory signature;

        // Parse userOp to extract sender, callData, and signature
        try this._decodeUserOp(userOp) returns (
            address _sender, bytes memory _callData, bytes memory _sig
        ) {
            sender = _sender;
            callData = _callData;
            signature = _sig;
        } catch {
            return VALIDATION_FAILED;
        }

        // Extract session key from signature (first 20 bytes)
        if (signature.length < 85) return VALIDATION_FAILED;
        address extractedSessionKey = address(bytes20(_sliceBytes(signature, 0, 20)));

        // Get session data for the sender (the smart account)
        SessionData storage session = sessions[sender];

        // Verify session key matches
        if (session.sessionKey != extractedSessionKey) {
            return VALIDATION_FAILED;
        }

        // Verify session is active
        if (!session.active) {
            return VALIDATION_FAILED;
        }

        // Verify session has not expired
        if (block.timestamp > session.validUntil) {
            return VALIDATION_FAILED;
        }

        // Extract function selector from callData
        if (callData.length < 4) return VALIDATION_FAILED;
        bytes4 selector = bytes4(_sliceBytes(callData, 0, 4));

        // Verify selector is allowed
        bool selectorAllowed = false;
        for (uint256 i = 0; i < session.allowedSelectors.length; i++) {
            if (session.allowedSelectors[i] == selector) {
                selectorAllowed = true;
                break;
            }
        }
        if (!selectorAllowed) {
            return VALIDATION_FAILED;
        }

        // For openPosition, decode collateral and check spend limit
        if (selector == OPEN_POSITION_SELECTOR) {
            // openPosition(bool isLong, uint256 collateral, uint256 leverage, PriceBounds calldata bounds)
            // Calldata layout:
            // [0:4]    selector
            // [4:36]   isLong (bool, padded to 32 bytes)
            // [36:68]  collateral (uint256)
            // [68:100] leverage (uint256)
            // [100+]   PriceBounds offset and data

            if (callData.length < 68) return VALIDATION_FAILED;

            uint256 collateral = uint256(bytes32(_sliceBytes(callData, 36, 68)));

            // Check spend limit
            if (session.spentAmount + collateral > session.spendLimit) {
                return VALIDATION_FAILED;
            }

            // Update spent amount
            session.spentAmount += collateral;
        }
        // For closePosition, no spend tracking needed

        // Verify ECDSA signature
        // Extract ECDSA signature from signature bytes (bytes 20-85)
        bytes memory ecdsaSig = _sliceBytes(signature, 20, 85);

        // Recover signer from signature
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address recovered = ECDSA.recover(ethSignedHash, ecdsaSig);

        if (recovered != extractedSessionKey) {
            return VALIDATION_FAILED;
        }

        return VALIDATION_SUCCESS;
    }

    /// @notice Helper function to decode PackedUserOperation.
    /// @dev This is a public function to allow try-catch in validateUserOp.
    function _decodeUserOp(bytes calldata userOp)
        public
        pure
        returns (address sender, bytes memory callData, bytes memory signature)
    {
        (sender,,, callData,,,,, signature) = abi.decode(
            userOp, (address, uint256, bytes, bytes, bytes32, uint256, bytes32, bytes, bytes)
        );
    }

    /// @notice Helper function to slice bytes.
    /// @param data The bytes to slice.
    /// @param start The start index.
    /// @param end The end index (exclusive).
    /// @return The sliced bytes.
    function _sliceBytes(bytes memory data, uint256 start, uint256 end)
        internal
        pure
        returns (bytes memory)
    {
        require(end <= data.length, "Slice out of bounds");
        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /// @inheritdoc ISessionKeyValidator
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        // Extract session key from signature (first 20 bytes)
        if (signature.length < 85) return ERC1271_INVALID;

        bytes memory sigBytes = bytes(signature);
        address extractedSessionKey = address(bytes20(_sliceBytes(sigBytes, 0, 20)));

        // Get session data
        SessionData storage session = sessions[sender];

        // Verify session key matches
        if (session.sessionKey != extractedSessionKey) {
            return ERC1271_INVALID;
        }

        // Verify session is active
        if (!session.active) {
            return ERC1271_INVALID;
        }

        // Verify session has not expired
        if (block.timestamp > session.validUntil) {
            return ERC1271_INVALID;
        }

        // Extract ECDSA signature (bytes 20-85)
        bytes memory ecdsaSig = _sliceBytes(sigBytes, 20, 85);

        // Recover signer
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address recovered = ECDSA.recover(ethSignedHash, ecdsaSig);

        if (recovered != extractedSessionKey) {
            return ERC1271_INVALID;
        }

        return ERC1271_MAGIC_VALUE;
    }

    /// @inheritdoc ISessionKeyValidator
    function onInstall(bytes calldata data) external {
        // No-op: session data is managed via grantSession
        (data);
    }

    /// @inheritdoc ISessionKeyValidator
    function onUninstall(bytes calldata data) external {
        // No-op: session data persists; use revokeSession to disable
        (data);
    }

    /// @inheritdoc ISessionKeyValidator
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }
}
