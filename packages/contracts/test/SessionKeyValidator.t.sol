// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { ISessionKeyValidator } from "src/interfaces/ISessionKeyValidator.sol";

/// @dev Full test suite for SessionKeyValidator.
contract SessionKeyValidatorTest is Test {
    SessionKeyValidator internal validator;

    address internal owner;
    uint256 internal ownerKey;

    address internal sessionKey;
    uint256 internal sessionKeyPrivKey;

    address internal perpEngine = 0xe35486669A5D905CF18D4af477Aaac08dF93Eab0;
    address internal mockUSDC = 0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB;

    bytes4 internal constant OPEN_POSITION_SELECTOR = 0x5a6c3d4a;
    bytes4 internal constant CLOSE_POSITION_SELECTOR = 0x5c36b186;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (sessionKey, sessionKeyPrivKey) = makeAddrAndKey("sessionKey");
        validator = new SessionKeyValidator();
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Create a valid openPosition calldata.
    function _createOpenPositionCalldata(bool isLong, uint256 collateral, uint256 leverage)
        internal
        pure
        returns (bytes memory)
    {
        // openPosition(bool isLong, uint256 collateral, uint256 leverage, PriceBounds calldata bounds)
        // We'll create minimal calldata without the PriceBounds struct for testing
        bytes memory calldata_ = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            isLong,
            collateral,
            leverage,
            uint256(0), // expectedPrice (placeholder)
            uint256(0), // maxDeviation (placeholder)
            uint256(0) // deadline (placeholder)
        );
        return calldata_;
    }

    /// @dev Create a valid closePosition calldata.
    function _createClosePositionCalldata(uint256 positionId) internal pure returns (bytes memory) {
        bytes memory calldata_ = abi.encodeWithSelector(
            CLOSE_POSITION_SELECTOR,
            positionId,
            uint256(0), // expectedPrice (placeholder)
            uint256(0), // maxDeviation (placeholder)
            uint256(0) // deadline (placeholder)
        );
        return calldata_;
    }

    /// @dev Create a mock PackedUserOperation.
    function _createPackedUserOp(address sender, bytes memory callData, bytes memory signature)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            sender, // sender
            uint256(0), // nonce
            bytes(""), // initCode
            callData, // callData
            bytes32(0), // accountGasLimits
            uint256(0), // preVerificationGas
            bytes32(0), // gasFees
            bytes(""), // paymasterAndData
            signature // signature
        );
    }

    /// @dev Create a valid signature for a userOpHash.
    function _createSignature(bytes32 userOpHash) internal view returns (bytes memory) {
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivKey, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);

        // Combine sessionKey (20 bytes) + ecdsaSig (65 bytes)
        return abi.encodePacked(sessionKey, ecdsaSig);
    }

    // ─── Unit Tests: Happy Path ───────────────────────────────────────────────

    function test_GrantSession_SetsData() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = OPEN_POSITION_SELECTOR;
        selectors[1] = CLOSE_POSITION_SELECTOR;

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint256 spendLimit = 10_000e6; // 10k USDC

        vm.prank(owner);
        validator.grantSession(sessionKey, validUntil, perpEngine, selectors, spendLimit);

        ISessionKeyValidator.SessionData memory session = validator.getSession(owner);
        assertEq(session.sessionKey, sessionKey);
        assertEq(session.validUntil, validUntil);
        assertEq(session.targetContract, perpEngine);
        assertEq(session.spendLimit, spendLimit);
        assertEq(session.spentAmount, 0);
        assertTrue(session.active);
        assertEq(session.allowedSelectors.length, 2);
    }

    function test_RevokeSession_SetsInactive() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;

        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        vm.prank(owner);
        validator.revokeSession();

        ISessionKeyValidator.SessionData memory session = validator.getSession(owner);
        assertFalse(session.active);
    }

    function test_ValidateUserOp_ValidSession_ReturnsSuccess() public {
        // Grant session
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Create userOp
        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        // Validate
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // VALIDATION_SUCCESS
    }

    function test_ValidateUserOp_OpenPosition_TracksSpend() public {
        // Grant session with 5k USDC limit
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 5_000e6
        );

        // First openPosition: 2k USDC
        bytes memory callData1 = _createOpenPositionCalldata(true, 2_000e6, 10);
        bytes32 userOpHash1 = keccak256("hash1");
        bytes memory signature1 = _createSignature(userOpHash1);
        bytes memory userOp1 = _createPackedUserOp(owner, callData1, signature1);

        uint256 result1 = validator.validateUserOp(userOp1, userOpHash1);
        assertEq(result1, 0);

        ISessionKeyValidator.SessionData memory session1 = validator.getSession(owner);
        assertEq(session1.spentAmount, 2_000e6);

        // Second openPosition: 2.5k USDC (total 4.5k, within limit)
        bytes memory callData2 = _createOpenPositionCalldata(true, 2_500e6, 10);
        bytes32 userOpHash2 = keccak256("hash2");
        bytes memory signature2 = _createSignature(userOpHash2);
        bytes memory userOp2 = _createPackedUserOp(owner, callData2, signature2);

        uint256 result2 = validator.validateUserOp(userOp2, userOpHash2);
        assertEq(result2, 0);

        ISessionKeyValidator.SessionData memory session2 = validator.getSession(owner);
        assertEq(session2.spentAmount, 4_500e6);
    }

    function test_ValidateUserOp_ClosePosition_NoSpendTracking() public {
        // Grant session
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = CLOSE_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // closePosition should not track spend
        bytes memory callData = _createClosePositionCalldata(1);
        bytes32 userOpHash = keccak256("close_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0);

        ISessionKeyValidator.SessionData memory session = validator.getSession(owner);
        assertEq(session.spentAmount, 0); // No spend tracked
    }

    // ─── Unit Tests: Error Cases ──────────────────────────────────────────────

    function test_ValidateUserOp_ExpiredSession_ReturnsFailed() public {
        // Grant session that expires immediately
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp - 1), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_ValidateUserOp_RevokedSession_ReturnsFailed() public {
        // Grant and then revoke
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        vm.prank(owner);
        validator.revokeSession();

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_ValidateUserOp_WrongSessionKey_ReturnsFailed() public {
        // Grant session with one key
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Create signature with different key
        (address wrongKey, uint256 wrongKeyPriv) = makeAddrAndKey("wrongKey");
        bytes32 userOpHash = keccak256("test_hash");
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKeyPriv, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory wrongSignature = abi.encodePacked(wrongKey, ecdsaSig);

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes memory userOp = _createPackedUserOp(owner, callData, wrongSignature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_ValidateUserOp_WrongSelector_ReturnsFailed() public {
        // Grant session with only openPosition selector
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Try to call closePosition
        bytes memory callData = _createClosePositionCalldata(1);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_ValidateUserOp_SpendLimitExceeded_ReturnsFailed() public {
        // Grant session with 1k USDC limit
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 1_000e6
        );

        // Try to spend 2k USDC
        bytes memory callData = _createOpenPositionCalldata(true, 2_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_GrantSession_ZeroSessionKey_Reverts() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;

        vm.prank(owner);
        vm.expectRevert(ISessionKeyValidator.ZeroAddress.selector);
        validator.grantSession(
            address(0), uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );
    }

    function test_GrantSession_ZeroTargetContract_Reverts() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;

        vm.prank(owner);
        vm.expectRevert(ISessionKeyValidator.ZeroAddress.selector);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), address(0), selectors, 10_000e6
        );
    }

    function test_GrantSession_AlreadyGranted_Reverts() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;

        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionKeyValidator.SessionAlreadyGranted.selector, owner)
        );
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );
    }

    // ─── ERC-1271 Tests ───────────────────────────────────────────────────────

    function test_IsValidSignatureWithSender_ValidSignature_ReturnsMagicValue() public {
        // Grant session
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Create valid signature
        bytes32 hash = keccak256("test_message");
        bytes memory signature = _createSignature(hash);

        bytes4 result = validator.isValidSignatureWithSender(owner, hash, signature);
        assertEq(result, bytes4(0x1626ba7e)); // ERC1271_MAGIC_VALUE
    }

    function test_IsValidSignatureWithSender_InvalidSignature_ReturnsInvalid() public {
        // Grant session
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Create signature with wrong key
        (address wrongKey, uint256 wrongKeyPriv) = makeAddrAndKey("wrongKey");
        bytes32 hash = keccak256("test_message");
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKeyPriv, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory wrongSignature = abi.encodePacked(wrongKey, ecdsaSig);

        bytes4 result = validator.isValidSignatureWithSender(owner, hash, wrongSignature);
        assertEq(result, bytes4(0xffffffff)); // ERC1271_INVALID
    }

    // ─── Module Type Tests ────────────────────────────────────────────────────

    function test_IsModuleType_ValidatorType_ReturnsTrue() public {
        assertTrue(validator.isModuleType(1)); // MODULE_TYPE_VALIDATOR
    }

    function test_IsModuleType_InvalidType_ReturnsFalse() public {
        assertFalse(validator.isModuleType(0));
        assertFalse(validator.isModuleType(2));
        assertFalse(validator.isModuleType(999));
    }

    // ─── Fuzz Tests ───────────────────────────────────────────────────────────

    function test_fuzz_ValidateUserOp_RandomValidUntil(uint48 validUntil) public {
        // Ensure validUntil is in a reasonable range
        validUntil = uint48(bound(validUntil, block.timestamp, block.timestamp + 365 days));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(sessionKey, validUntil, perpEngine, selectors, 10_000e6);

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // Should succeed since validUntil is in the future
    }

    function test_fuzz_ValidateUserOp_RandomCollateral(uint256 collateral) public {
        // Bound collateral to reasonable range (1 USDC to 1M USDC)
        collateral = bound(collateral, 1e6, 1_000_000e6);

        uint256 spendLimit = collateral + 1_000e6; // Ensure limit is above collateral

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, spendLimit
        );

        bytes memory callData = _createOpenPositionCalldata(true, collateral, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // Should succeed
    }

    function test_fuzz_ValidateUserOp_RandomSpendLimit(uint256 spendLimit) public {
        // Bound spend limit
        spendLimit = bound(spendLimit, 1e6, 10_000_000e6);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, spendLimit
        );

        // Use a collateral that's within the limit
        uint256 collateral = spendLimit / 2;

        bytes memory callData = _createOpenPositionCalldata(true, collateral, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // Should succeed
    }

    function test_fuzz_ValidateUserOp_ExceedsSpendLimit(uint256 collateral, uint256 spendLimit)
        public
    {
        // Ensure collateral > spendLimit (collateral min 2e6 so spendLimit range [1e6, collateral-1] is valid)
        collateral = bound(collateral, 2e6, 10_000_000e6);
        spendLimit = bound(spendLimit, 1e6, collateral - 1);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, spendLimit
        );

        bytes memory callData = _createOpenPositionCalldata(true, collateral, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        bytes memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // Should fail
    }
}
