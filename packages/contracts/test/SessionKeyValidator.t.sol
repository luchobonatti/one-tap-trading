// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { ISessionKeyValidator } from "src/interfaces/ISessionKeyValidator.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";

/// @dev Full test suite for SessionKeyValidator.
contract SessionKeyValidatorTest is Test {
    SessionKeyValidator internal validator;

    address internal owner;
    uint256 internal ownerKey;

    address internal sessionKey;
    uint256 internal sessionKeyPrivKey;

    address internal perpEngine = 0xe35486669A5D905CF18D4af477Aaac08dF93Eab0;
    address internal mockUSDC = 0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB;

    // Correct selectors matching PerpEngine ABI (keccak256 of full signatures)
    bytes4 internal constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));
    bytes4 internal constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));
    // Kernel v3 ERC-7579 execute selector
    bytes4 internal constant KERNEL_EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes32,bytes)"));

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (sessionKey, sessionKeyPrivKey) = makeAddrAndKey("sessionKey");
        validator = new SessionKeyValidator();
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /// @dev Wrap inner callData in Kernel v3 ERC-7579 execute(bytes32,bytes) single-call format.
    function _wrapExecute(address target, bytes memory innerCallData)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory execCalldata = abi.encodePacked(target, uint256(0), innerCallData);
        return abi.encodeWithSelector(
            KERNEL_EXECUTE_SELECTOR,
            bytes32(0), // single-call mode (callType 0x00)
            execCalldata
        );
    }

    /// @dev Create wrapped openPosition callData (ERC-7579 execute around PerpEngine call).
    function _createOpenPositionCalldata(bool isLong, uint256 collateral, uint256 leverage)
        internal
        view
        returns (bytes memory)
    {
        bytes memory inner = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            isLong,
            collateral,
            leverage,
            uint256(0), // expectedPrice (placeholder)
            uint256(0), // maxDeviation (placeholder)
            uint256(0) // deadline (placeholder)
        );
        return _wrapExecute(perpEngine, inner);
    }

    /// @dev Create wrapped closePosition callData (ERC-7579 execute around PerpEngine call).
    function _createClosePositionCalldata(uint256 positionId) internal view returns (bytes memory) {
        bytes memory inner = abi.encodeWithSelector(
            CLOSE_POSITION_SELECTOR,
            positionId,
            uint256(0), // expectedPrice
            uint256(0), // maxDeviation
            uint256(0) // deadline
        );
        return _wrapExecute(perpEngine, inner);
    }

    /// @dev Create a mock PackedUserOperation struct.
    function _createPackedUserOp(address sender, bytes memory callData, bytes memory signature)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });
    }

    /// @dev Create a valid UserOp signature (Kernel v3.1 SECONDARY mode) for validateUserOp.
    ///      Format: mode(0x01) + validatorAddress(20B) + sessionKeyAddress(20B) + ecdsaSig(65B)
    ///      = 106 bytes total.
    ///      This is the format the validator receives when called from Kernel v3.1.
    function _createSignature(bytes32 userOpHash) internal view returns (bytes memory) {
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivKey, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        // Kernel v3.1 SECONDARY validator signature:
        //   mode(0x01) + validatorAddr(20B) + sessionKey(20B) + ecdsaSig(65B) = 106 bytes
        return abi.encodePacked(bytes1(0x01), address(validator), sessionKey, ecdsaSig);
    }

    /// @dev Create an ERC-1271 signature for isValidSignatureWithSender (no mode byte).
    ///      Format: sessionKeyAddress(20B) + ecdsaSig(65B) = 85 bytes.
    function _createERC1271Signature(bytes32 hash) internal view returns (bytes memory) {
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivKey, ethSignedHash);
        return abi.encodePacked(sessionKey, abi.encodePacked(r, s, v));
    }

    // ─── Unit Tests: Happy Path ───────────────────────────────────────────────

    function test_GrantSession_SetsData() public {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = OPEN_POSITION_SELECTOR;
        selectors[1] = CLOSE_POSITION_SELECTOR;

        uint48 validUntil = uint48(block.timestamp + 1 days);
        uint256 spendLimit = 10_000e6;

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
        assertEq(session.allowedSelectors[0], OPEN_POSITION_SELECTOR);
        assertEq(session.allowedSelectors[1], CLOSE_POSITION_SELECTOR);
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
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        bytes memory signature = _createSignature(userOpHash);
        PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, signature);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0); // VALIDATION_SUCCESS
    }

    function test_ValidateUserOp_OpenPosition_TracksSpend() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 5_000e6
        );

        // First openPosition: 2k USDC
        bytes memory callData1 = _createOpenPositionCalldata(true, 2_000e6, 10);
        bytes32 userOpHash1 = keccak256("hash1");
        PackedUserOperation memory userOp1 =
            _createPackedUserOp(owner, callData1, _createSignature(userOpHash1));

        uint256 result1 = validator.validateUserOp(userOp1, userOpHash1);
        assertEq(result1, 0);
        assertEq(validator.getSession(owner).spentAmount, 2_000e6);

        // Second openPosition: 2.5k USDC (total 4.5k, within limit)
        bytes memory callData2 = _createOpenPositionCalldata(true, 2_500e6, 10);
        bytes32 userOpHash2 = keccak256("hash2");
        PackedUserOperation memory userOp2 =
            _createPackedUserOp(owner, callData2, _createSignature(userOpHash2));

        uint256 result2 = validator.validateUserOp(userOp2, userOpHash2);
        assertEq(result2, 0);
        assertEq(validator.getSession(owner).spentAmount, 4_500e6);
    }

    function test_ValidateUserOp_ClosePosition_NoSpendTracking() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = CLOSE_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createClosePositionCalldata(1);
        bytes32 userOpHash = keccak256("close_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0);
        assertEq(validator.getSession(owner).spentAmount, 0); // No spend tracked
    }

    // ─── Unit Tests: Error Cases ──────────────────────────────────────────────

    function test_ValidateUserOp_ExpiredSession_ReturnsFailed() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp - 1), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED
    }

    function test_ValidateUserOp_RevokedSession_ReturnsFailed() public {
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
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }

    function test_ValidateUserOp_WrongSessionKey_ReturnsFailed() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        (address wrongKey, uint256 wrongKeyPriv) = makeAddrAndKey("wrongKey");
        bytes32 userOpHash = keccak256("test_hash");
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKeyPriv, ethSignedHash);
        // New 106-byte format: mode(0x01) + validatorAddr(20B) + wrongKey(20B) + ecdsaSig(65B)
        bytes memory wrongSig =
            abi.encodePacked(bytes1(0x01), address(validator), wrongKey, abi.encodePacked(r, s, v));

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, wrongSig);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }

    function test_ValidateUserOp_WrongSelector_ReturnsFailed() public {
        // Session only allows openPosition, but callData has closePosition
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createClosePositionCalldata(1);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }

    function test_ValidateUserOp_WrongTarget_ReturnsFailed() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Wrap callData targeting mockUSDC instead of perpEngine
        bytes memory inner = abi.encodeWithSelector(OPEN_POSITION_SELECTOR, true, 1_000e6, 10);
        bytes memory callData = _wrapExecute(mockUSDC, inner); // wrong target
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }

    function test_ValidateUserOp_SpendLimitExceeded_ReturnsFailed() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 1_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 2_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }

    function test_ValidateUserOp_InvalidSigDoesNotIncrementSpend() public {
        // Verify ECDSA-before-state-mutation: a caller with the correct sessionKey address but
        // a bad ECDSA signature must NOT be able to increment spentAmount (griefing protection).
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");

        // Build a signature that encodes the correct sessionKey address but uses a different
        // private key for the ECDSA portion — this should fail without touching spentAmount.
        (, uint256 otherPriv) = makeAddrAndKey("otherKey");
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPriv, ethSignedHash);
        // New 106-byte format: correct sessionKey addr but wrong ECDSA private key.
        bytes memory badSig = abi.encodePacked(
            bytes1(0x01), address(validator), sessionKey, abi.encodePacked(r, s, v)
        );

        PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, badSig);
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // VALIDATION_FAILED

        // spentAmount must remain zero — no state mutation occurred.
        assertEq(validator.getSession(owner).spentAmount, 0);
    }

    function test_ValidateUserOp_NotWrappedInExecute_ReturnsFailed() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        // Pass raw inner callData without execute wrapper — validator should reject
        bytes memory rawCallData = abi.encodeWithSelector(OPEN_POSITION_SELECTOR, true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, rawCallData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1); // Outer selector != KERNEL_EXECUTE_SELECTOR
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
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes32 hash = keccak256("test_message");
        bytes memory signature = _createERC1271Signature(hash);

        bytes4 result = validator.isValidSignatureWithSender(owner, hash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_IsValidSignatureWithSender_InvalidSignature_ReturnsInvalid() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        (address wrongKey, uint256 wrongKeyPriv) = makeAddrAndKey("wrongKey");
        bytes32 hash = keccak256("test_message");
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKeyPriv, ethSignedHash);
        bytes memory wrongSig = abi.encodePacked(wrongKey, abi.encodePacked(r, s, v));

        bytes4 result = validator.isValidSignatureWithSender(owner, hash, wrongSig);
        assertEq(result, bytes4(0xffffffff));
    }

    // ─── Module Type Tests ────────────────────────────────────────────────────

    function test_IsModuleType_ValidatorType_ReturnsTrue() public {
        assertTrue(validator.isModuleType(1));
    }

    function test_IsModuleType_InvalidType_ReturnsFalse() public {
        assertFalse(validator.isModuleType(0));
        assertFalse(validator.isModuleType(2));
        assertFalse(validator.isModuleType(999));
    }

    // ─── Signature Format Regression Tests ───────────────────────────────────
    //
    // These tests verify that SessionKeyValidator.validateUserOp correctly enforces
    // the 106-byte SECONDARY-mode signature layout:
    //   0x01(1B) + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B) = 106 bytes
    //
    // Note: these tests call validateUserOp directly — they do NOT route through
    // Kernel and therefore cannot observe Kernel's forwarding behaviour.
    // They serve as a format regression guard: the 106-byte layout must pass,
    // the 85-byte (old stripped) layout must fail.
    //
    // Byte count: 0x01(1) + validatorAddr(20) + sessionKeyAddr(20) + ecdsaSig(65) = 106.
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Scenario A — old 85-byte format (no mode byte, no validator address).
    ///      Calls validateUserOp directly with sessionKeyAddr(20B) + ecdsaSig(65B).
    ///      Expected to FAIL: 85 < 106 minimum length enforced by the new contract.
    function test_Diagnostic_NewSig_DirectCallScenarioA() public {
        address skv = address(validator);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("diagnostic_a");

        // 85-byte sig: no mode byte, no validator addr — what validator would see if
        // Kernel stripped the 21-byte prefix.
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivKey, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        bytes memory sig85 = abi.encodePacked(sessionKey, ecdsaSig); // 20 + 65 = 85 bytes
        assertEq(sig85.length, 85, "Scenario A sig must be 85 bytes");

        PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, sig85);

        // 85 < 106 (new minimum length) → VALIDATION_FAILED.
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1, "Scenario A: 85-byte sig rejected by new 106-byte contract");

        (skv);
    }

    /// @dev Scenario B — correct 106-byte format: 0x01 + validatorAddr + sessionKeyAddr + ecdsaSig.
    ///      Calls validateUserOp with 0x01 + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B).
    ///      Expected to PASS — this is the correct production format.
    ///      Note: 0x01(1B) + addr(20B) + addr(20B) + ecdsa(65B) = 106 bytes.
    function test_Diagnostic_NewSig_DirectCallScenarioB() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6
        );

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("diagnostic_b");

        // 106-byte sig: 0x01 + SKV address (20B) + sessionKey address (20B) + ecdsaSig (65B)
        // 1 + 20 + 20 + 65 = 106 bytes total.
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivKey, ethSignedHash);
        bytes memory ecdsaSig = abi.encodePacked(r, s, v);
        address validatorAddr = address(validator);
        bytes memory sig106 = abi.encodePacked(bytes1(0x01), validatorAddr, sessionKey, ecdsaSig);
        assertEq(sig106.length, 106, "Scenario B sig must be 106 bytes");

        PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, sig106);

        // Under the new contract: sessionKey read from [21:41], ecdsaSig from [41:106].
        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0, "Scenario B: 106-byte sig succeeds (confirmed production format)");
    }

    // ─── Fuzz Tests ───────────────────────────────────────────────────────────

    function test_fuzz_ValidateUserOp_RandomValidUntil(uint48 validUntil) public {
        validUntil = uint48(bound(validUntil, block.timestamp, block.timestamp + 365 days));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(sessionKey, validUntil, perpEngine, selectors, 10_000e6);

        bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0);
    }

    function test_fuzz_ValidateUserOp_RandomCollateral(uint256 collateral) public {
        collateral = bound(collateral, 1e6, 1_000_000e6);
        uint256 spendLimit = collateral + 1_000e6;

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, spendLimit
        );

        bytes memory callData = _createOpenPositionCalldata(true, collateral, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0);
    }

    function test_fuzz_ValidateUserOp_RandomSpendLimit(uint256 spendLimit) public {
        spendLimit = bound(spendLimit, 1e6, 10_000_000e6);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = OPEN_POSITION_SELECTOR;
        vm.prank(owner);
        validator.grantSession(
            sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, spendLimit
        );

        uint256 collateral = spendLimit / 2;
        bytes memory callData = _createOpenPositionCalldata(true, collateral, 10);
        bytes32 userOpHash = keccak256("test_hash");
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0);
    }

    function test_fuzz_ValidateUserOp_ExceedsSpendLimit(uint256 collateral, uint256 spendLimit)
        public
    {
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
        PackedUserOperation memory userOp =
            _createPackedUserOp(owner, callData, _createSignature(userOpHash));

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1);
    }
}
