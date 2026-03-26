// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ISessionKeyValidator } from "./interfaces/ISessionKeyValidator.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @title SessionKeyValidator
/// @notice ERC-7579 validator module for session key authorization in One Tap Trading.
///         Enforces ephemeral ECDSA key permissions for PerpEngine operations.
///
///         Trading UserOps from Kernel v3 arrive as execute(bytes32 mode, bytes execCalldata)
///         where execCalldata = abi.encodePacked(target, value, innerCallData).  This
///         validator unwraps the outer execute call before checking the inner selector and
///         deriving the collateral amount for spend-limit tracking.
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

    /// @notice Kernel v3 ERC-7579 execute(bytes32,bytes) selector.
    bytes4 private constant KERNEL_EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes32,bytes)"));

    /// @notice PerpEngine openPosition selector (keccak256 of full signature).
    bytes4 private constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));

    /// @notice PerpEngine closePosition selector (keccak256 of full signature).
    bytes4 private constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));

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
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        returns (uint256)
    {
        bytes calldata signature = userOp.signature;

        // Kernel v3 passes the full signature including the 1-byte mode prefix (e.g. 0x00 for
        // DEFAULT). Strip the mode byte: actual session signature starts at offset 1.
        // Format: mode(1B) + sessionKeyAddress(20B) + ecdsaSig(65B) = 86 bytes minimum.
        if (signature.length < 86) return VALIDATION_FAILED;

        address extractedSessionKey = address(bytes20(signature[1:21]));

        address sender = userOp.sender;
        SessionData storage session = sessions[sender];
        if (session.sessionKey != extractedSessionKey) return VALIDATION_FAILED;
        if (!session.active) return VALIDATION_FAILED;
        if (block.timestamp > session.validUntil) return VALIDATION_FAILED;

        // Unwrap ERC-7579 execute and validate call — extracted to avoid stack-too-deep.
        (address callTarget, bytes memory innerCallData) = _unwrapExecuteCall(userOp.callData);
        if (innerCallData.length < 4) return VALIDATION_FAILED;
        if (callTarget != session.targetContract) return VALIDATION_FAILED;

        bytes4 selector = bytes4(
            abi.encodePacked(innerCallData[0], innerCallData[1], innerCallData[2], innerCallData[3])
        );
        if (!_isSelectorAllowed(selector, session.allowedSelectors)) return VALIDATION_FAILED;

        // Verify ECDSA signature before mutating state.
        // Doing this first prevents a griefing attack where an attacker passes the correct
        // sessionKey address but an invalid ECDSA signature, incrementing spentAmount and
        // locking the session without ever being authorised.
        if (!_verifyEcdsa(userOpHash, signature[21:86], extractedSessionKey)) {
            return VALIDATION_FAILED;
        }

        // Only after signature is verified: enforce spend limit and update state.
        // innerCallData layout: [0:4] selector, [4:36] isLong, [36:68] collateral.
        if (selector == OPEN_POSITION_SELECTOR) {
            if (innerCallData.length < 68) return VALIDATION_FAILED;
            uint256 collateral = abi.decode(_sliceBytes(innerCallData, 36, 68), (uint256));
            if (session.spentAmount + collateral > session.spendLimit) return VALIDATION_FAILED;
            session.spentAmount += collateral;
        }

        return VALIDATION_SUCCESS;
    }

    /// @notice Unwrap a Kernel v3 ERC-7579 execute(bytes32,bytes) single call.
    ///         execCalldata = abi.encodePacked(address target, uint256 value, bytes innerCallData)
    ///         Returns (address(0), "") on parse failure.
    function _unwrapExecuteCall(bytes memory rawCallData)
        internal
        pure
        returns (address target, bytes memory innerCallData)
    {
        if (rawCallData.length < 4) return (address(0), "");

        bytes4 outer = bytes4(
            abi.encodePacked(rawCallData[0], rawCallData[1], rawCallData[2], rawCallData[3])
        );
        if (outer != KERNEL_EXECUTE_SELECTOR) return (address(0), "");

        if (rawCallData.length < 100) return (address(0), "");

        (, bytes memory execCalldata) =
            abi.decode(_sliceBytes(rawCallData, 4, rawCallData.length), (bytes32, bytes));

        if (execCalldata.length < 56) return (address(0), "");

        bytes memory targetPadded = abi.encodePacked(bytes12(0), _sliceBytes(execCalldata, 0, 20));
        target = abi.decode(targetPadded, (address));
        innerCallData = _sliceBytes(execCalldata, 52, execCalldata.length);
    }

    /// @notice Check whether `selector` appears in `allowedSelectors`.
    function _isSelectorAllowed(bytes4 selector, bytes4[] memory allowedSelectors)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < allowedSelectors.length; ++i) {
            if (allowedSelectors[i] == selector) return true;
        }
        return false;
    }

    /// @notice Verify an ECDSA signature using eth_sign message hash.
    function _verifyEcdsa(bytes32 msgHash, bytes memory sig, address expectedSigner)
        internal
        pure
        returns (bool)
    {
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(msgHash);
        return ECDSA.recover(ethHash, sig) == expectedSigner;
    }

    /// @notice Slice a bytes memory array from [start, end).
    function _sliceBytes(bytes memory data, uint256 start, uint256 end)
        internal
        pure
        returns (bytes memory)
    {
        require(end <= data.length, "Slice out of bounds");
        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < end - start; ++i) {
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
        if (signature.length < 85) return ERC1271_INVALID;

        bytes memory sigBytes = bytes(signature);
        address extractedSessionKey = address(bytes20(_sliceBytes(sigBytes, 0, 20)));

        SessionData storage session = sessions[sender];

        if (session.sessionKey != extractedSessionKey) return ERC1271_INVALID;
        if (!session.active) return ERC1271_INVALID;
        if (block.timestamp > session.validUntil) return ERC1271_INVALID;

        bytes memory ecdsaSig = _sliceBytes(sigBytes, 20, 85);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address recovered = ECDSA.recover(ethSignedHash, ecdsaSig);

        if (recovered != extractedSessionKey) return ERC1271_INVALID;
        return ERC1271_MAGIC_VALUE;
    }

    /// @inheritdoc ISessionKeyValidator
    function onInstall(bytes calldata data) external pure {
        // No-op: session data is managed via grantSession
        (data);
    }

    /// @inheritdoc ISessionKeyValidator
    function onUninstall(bytes calldata data) external pure {
        // No-op: session data persists; use revokeSession to disable
        (data);
    }

    /// @inheritdoc ISessionKeyValidator
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }
}
