# Design: Session Key Trade Fix

## Technical Approach

The session key validator currently uses signature mode `0x00` (Kernel DEFAULT/WebAuthn mode) instead of `0x01` (SECONDARY validator mode). This mismatch causes Kernel v3.1 to route the signature to the wrong handler, resulting in validation failures.

The fix involves:
1. **Diagnostic test** to determine if Kernel v3.1 strips the signature prefix (first 21 bytes: `0x01` + validatorAddress) before calling `validateUserOp`
2. **Signature format change** in `signer.ts` to use `0x01` mode with the validator address
3. **Offset adjustment** in `SessionKeyValidator.sol` based on the diagnostic result
4. **Stub signature update** for gas estimation to match the new format

This design resolves the critical open question: **Does Kernel v3.1 strip the first 21 bytes before calling the validator?**

## Architecture Decisions

### Decision 1: Signature Mode Selection (0x01 vs 0x00)

**Choice**: Use signature mode `0x01` (SECONDARY validator mode) instead of `0x00` (DEFAULT mode).

**Alternatives considered**:
- Keep `0x00` and debug why Kernel routes it incorrectly (requires Kernel source inspection, not actionable)
- Use a different mode entirely (no other modes apply to session key validators)

**Rationale**:
- Kernel v3.1 installs the SessionKeyValidator as a SECONDARY validator via `installValidations` with vId `0x01{address}` (see `session-key.ts:187`)
- The signature mode must match the validator type that was installed
- Using `0x01` aligns the signature format with the actual validator installation
- This is the standard ERC-7579 pattern: signature mode indicates which validator to invoke

---

### Decision 2: Diagnostic Test Design (Kernel Stripping Behavior)

**Choice**: Create a Foundry test that directly calls `SessionKeyValidator.validateUserOp` with two signature formats and observes the results.

**Test approach**:
```solidity
// Test 1: Signature WITH 0x01 prefix (107 bytes total)
// Format: 0x01 + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B)
// Expected: If Kernel strips, SKV receives 85 bytes and validates successfully
//           If Kernel doesn't strip, SKV receives 107 bytes and must handle offset 21

// Test 2: Signature WITHOUT 0x01 prefix (106 bytes total)
// Format: validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B)
// Expected: Opposite of Test 1

// Test 3: Direct call to validateUserOp with both formats
// Observe: Which format results in VALIDATION_SUCCESS (0)
```

**Alternatives considered**:
- Deploy to testnet and observe live behavior (slow, requires gas, less reproducible)
- Read Kernel v3.1 source code (time-consuming, may have version-specific behavior)
- Assume based on ERC-7579 spec (spec doesn't explicitly define stripping behavior)

**Rationale**:
- Foundry tests are deterministic, fast, and repeatable
- Direct calls to `validateUserOp` bypass any Kernel routing logic and test the validator in isolation
- The test result definitively answers the question without ambiguity
- This test becomes part of the permanent test suite and documents the assumption

---

### Decision 3: Signature Format in signer.ts

**Choice**:
```typescript
// New format: 0x01 + validatorAddress(20B) + sessionKeyAddress(20B) + ecdsaSig(65B) = 107 bytes
const signature = concat(["0x01", session.validatorAddress, session.address, ecdsaSig]) as Hex;
```

**Alternatives considered**:
- Keep current format `concat(["0x00", session.address, ecdsaSig])` (86 bytes) — doesn't match validator type
- Use only `concat([session.address, ecdsaSig])` (85 bytes) — loses mode information
- Include additional metadata — adds complexity without benefit

**Rationale**:
- The `0x01` byte explicitly signals SECONDARY validator mode to Kernel
- Including `session.validatorAddress` allows the validator to verify it's being called in the correct context
- The format is self-describing: mode + validator + session key + signature
- Matches the vId format used in `installValidations` (see `session-key.ts:187`)

**Offset breakdown**:
- Bytes [0:1]: `0x01` (mode)
- Bytes [1:21]: `session.validatorAddress` (20 bytes)
- Bytes [21:41]: `session.address` (20 bytes, the session key)
- Bytes [41:106]: `ecdsaSig` (65 bytes)
- Total: 107 bytes

---

### Decision 4: SessionKeyValidator.sol Offset Adjustment

**Choice**: Implement conditional offset handling based on diagnostic test result.

**If Kernel STRIPS the first 21 bytes** (most likely):
- SKV receives: `sessionKeyAddr(20B) + ecdsaSig(65B)` = 85 bytes
- Offsets in `validateUserOp`:
  ```solidity
  if (signature.length < 85) return VALIDATION_FAILED;
  address extractedSessionKey = address(bytes20(signature[0:20]));  // Changed from [1:21]
  if (!_verifyEcdsa(userOpHash, signature[20:85], extractedSessionKey)) {  // Changed from [21:86]
  ```
- Update `isValidSignatureWithSender` (already correct at [0:20] and [20:85])

**If Kernel DOES NOT strip** (less likely):
- SKV receives: `0x01 + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B)` = 107 bytes
- Offsets in `validateUserOp`:
  ```solidity
  if (signature.length < 107) return VALIDATION_FAILED;
  address extractedSessionKey = address(bytes20(signature[21:41]));  // Changed from [1:21]
  if (!_verifyEcdsa(userOpHash, signature[41:106], extractedSessionKey)) {  // Changed from [21:86]
  ```
- Add validation that `signature[0] == 0x01` and `signature[1:21] == expectedValidatorAddress`

**Alternatives considered**:
- Hardcode one format without testing (risky, may fail on deployment)
- Support both formats with runtime detection (adds complexity, unnecessary)
- Ask Kernel team (slow, may not get response)

**Rationale**:
- The diagnostic test definitively answers which scenario applies
- Offsets must match what Kernel actually passes to the validator
- The first scenario (Kernel strips) is more likely based on ERC-7579 patterns where the mode byte is consumed by the EntryPoint/Kernel before routing to the validator
- Conditional implementation ensures correctness regardless of Kernel behavior

---

### Decision 5: STUB_SESSION_SIGNATURE for Gas Estimation

**Choice**: Update stub to 107 bytes matching the new signature format.

**Current (incorrect)**:
```typescript
const STUB_SESSION_SIGNATURE = concat([
  "0x0000000000000000000000000000000000000000",  // 20 bytes of zeros
  "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",  // 65 bytes of zeros
]) as Hex;  // Total: 85 bytes
```

**New (correct)**:
```typescript
const STUB_SESSION_SIGNATURE = concat([
  "0x01",  // Mode byte
  "0x0000000000000000000000000000000000000000",  // Validator address (20 bytes of zeros)
  "0x0000000000000000000000000000000000000000",  // Session key address (20 bytes of zeros)
  "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",  // ECDSA sig (65 bytes of zeros)
]) as Hex;  // Total: 107 bytes
```

**Alternatives considered**:
- Use a valid signature (unnecessary, stub is only for length validation)
- Use a shorter stub (fails length check, breaks gas estimation)
- Keep current stub (causes validation failure during bundler simulation)

**Rationale**:
- The stub is used during `eth_estimateUserOperationGas` bundler simulation
- The bundler calls `validateUserOp` with the stub signature to estimate gas
- The stub only needs to pass length validation; the actual signature is provided later
- Using zeros is safe and efficient (no cryptographic operations on stub)
- The 107-byte length matches the final signature format

---

## Data Flow

```
User initiates trade
    ↓
buildUserOp(sender, callData, session)
    ├─ Nonce key: 0x0001{validatorAddress}0000 (already correct)
    └─ Signature: STUB_SESSION_SIGNATURE (107 bytes of zeros)
    ↓
signUserOp(userOp, session)
    ├─ Compute userOpHash
    ├─ Sign with session.privateKey
    └─ Signature: concat(["0x01", session.validatorAddress, session.address, ecdsaSig])
    ↓
submitUserOp(signedOp)
    ├─ Bundler receives UserOp with 107-byte signature
    ├─ Bundler calls EntryPoint.handleUserOps
    ├─ EntryPoint routes to Kernel (sender's smart account)
    ├─ Kernel extracts mode byte (0x01) and routes to SECONDARY validator
    ├─ Kernel calls SessionKeyValidator.validateUserOp
    │   ├─ Receives signature (either 85 or 107 bytes depending on Kernel stripping)
    │   ├─ Extracts session key address
    │   ├─ Verifies ECDSA signature
    │   ├─ Validates session, target, selector, spend limit
    │   └─ Returns VALIDATION_SUCCESS (0)
    └─ Kernel executes the inner call (openPosition/closePosition)
```

---

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `apps/web/src/lib/aa/signer.ts` | Modify | Update `signUserOp` to use `0x01` mode and include validatorAddress; update `STUB_SESSION_SIGNATURE` to 107 bytes |
| `packages/contracts/src/SessionKeyValidator.sol` | Modify | Adjust offsets in `validateUserOp` based on diagnostic test result; update length check from 86 to 85 or 107 |
| `packages/contracts/test/SessionKeyValidator.t.sol` | Modify | Add diagnostic test `test_DiagnosticKernelStripping_*` to determine Kernel behavior; update existing test signatures to 107 bytes |
| `packages/contracts/test/SessionKeyValidator.t.sol` | Modify | Update `_createSignature` helper to generate 107-byte signatures with `0x01` mode |

---

## Interfaces / Contracts

### Updated Signature Format

**In signer.ts (signUserOp)**:
```typescript
// Old: concat(["0x00", session.address, ecdsaSig])
// New: concat(["0x01", session.validatorAddress, session.address, ecdsaSig])

// Breakdown:
// [0:1]     = 0x01 (SECONDARY validator mode)
// [1:21]    = session.validatorAddress (20 bytes)
// [21:41]   = session.address (20 bytes, the ephemeral session key)
// [41:106]  = ecdsaSig (65 bytes, ECDSA signature)
// Total: 107 bytes
```

### SessionKeyValidator.validateUserOp Offsets

**Scenario A: Kernel strips first 21 bytes (MOST LIKELY)**
```solidity
// Receives: sessionKeyAddr(20B) + ecdsaSig(65B) = 85 bytes
if (signature.length < 85) return VALIDATION_FAILED;
address extractedSessionKey = address(bytes20(signature[0:20]));
if (!_verifyEcdsa(userOpHash, signature[20:85], extractedSessionKey)) {
    return VALIDATION_FAILED;
}
```

**Scenario B: Kernel does NOT strip (LESS LIKELY)**
```solidity
// Receives: 0x01 + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B) = 107 bytes
if (signature.length < 107) return VALIDATION_FAILED;
// Verify mode byte
if (signature[0] != 0x01) return VALIDATION_FAILED;
// Verify validator address matches
if (address(bytes20(signature[1:21])) != address(this)) return VALIDATION_FAILED;
address extractedSessionKey = address(bytes20(signature[21:41]));
if (!_verifyEcdsa(userOpHash, signature[41:106], extractedSessionKey)) {
    return VALIDATION_FAILED;
}
```

---

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| **Unit** | Diagnostic: Kernel stripping behavior | Create `test_DiagnosticKernelStripping_WithPrefix` and `test_DiagnosticKernelStripping_WithoutPrefix` that call `validateUserOp` directly with both signature formats and observe which passes |
| **Unit** | Signature validation with new format | Update `test_ValidateUserOp_ValidSession_ReturnsSuccess` to use 107-byte signatures with `0x01` mode |
| **Unit** | Offset correctness | Add `test_ValidateUserOp_ExtractsSessionKeyFromCorrectOffset` to verify session key extraction works with new offsets |
| **Unit** | Stub signature length | Add `test_StubSignatureLength_Is107Bytes` to verify stub is exactly 107 bytes |
| **Integration** | End-to-end trade flow | Existing integration tests should pass once offsets are corrected |
| **E2E** | Live testnet trade | Submit a real trade UserOp with new signature format and verify it executes |

### Diagnostic Test Pseudocode

```solidity
function test_DiagnosticKernelStripping_WithPrefix() public {
    // Setup: grant session
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = OPEN_POSITION_SELECTOR;
    vm.prank(owner);
    validator.grantSession(sessionKey, uint48(block.timestamp + 1 days), perpEngine, selectors, 10_000e6);

    // Create callData
    bytes memory callData = _createOpenPositionCalldata(true, 1_000e6, 10);
    bytes32 userOpHash = keccak256("test_hash");

    // Create signature WITH 0x01 prefix (107 bytes)
    bytes memory signature = abi.encodePacked(
        bytes1(0x01),
        session.validatorAddress,  // 20 bytes
        sessionKey,                  // 20 bytes
        ecdsaSig                     // 65 bytes
    );

    PackedUserOperation memory userOp = _createPackedUserOp(owner, callData, signature);
    uint256 result = validator.validateUserOp(userOp, userOpHash);

    // If Kernel strips: result should be VALIDATION_SUCCESS (0)
    // If Kernel doesn't strip: result should be VALIDATION_FAILED (1) with current offsets
    // This test determines which scenario is true
}

function test_DiagnosticKernelStripping_WithoutPrefix() public {
    // Same setup, but signature WITHOUT 0x01 prefix (85 bytes)
    bytes memory signature = abi.encodePacked(
        sessionKey,      // 20 bytes
        ecdsaSig         // 65 bytes
    );

    // Opposite result from WithPrefix test
}
```

---

## Migration / Rollout

**No migration required.** This is a bug fix that corrects the signature format to match the validator type that was installed. Existing sessions will be invalidated (they were already broken), and users will generate new sessions with the correct format.

**Rollout steps**:
1. Deploy diagnostic test to verify Kernel behavior
2. Update `SessionKeyValidator.sol` offsets based on diagnostic result
3. Update `signer.ts` signature format
4. Update test helpers to generate 107-byte signatures
5. Run full test suite to verify all tests pass
6. Deploy to testnet and verify end-to-end trade flow
7. Deploy to mainnet

---

## Open Questions

- [x] **Does Kernel v3.1 strip the first 21 bytes before calling validateUserOp?**
  - **Resolution**: Diagnostic test will answer this definitively
  - **Impact**: Determines offsets in SessionKeyValidator.sol
  - **Timeline**: Must be resolved before implementation

---

## Assumptions

1. **Kernel v3.1 uses ERC-7579 standard routing**: The mode byte in the signature is consumed by Kernel/EntryPoint before routing to the validator (most likely scenario based on ERC-7579 spec)
2. **Session key validator is installed as SECONDARY type**: Confirmed by `session-key.ts:187` which uses vId `0x01{address}`
3. **Bundler supports 107-byte signatures**: ZeroDev bundler v3 has no signature length restrictions
4. **ECDSA signature is always 65 bytes**: Standard for secp256k1 (r=32, s=32, v=1)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Diagnostic test doesn't definitively answer the question | Low | Blocks implementation | Design test to be unambiguous; if needed, deploy to testnet and observe live behavior |
| Kernel behavior differs from assumption | Low | Signature validation fails | Diagnostic test catches this before implementation |
| Offset calculation is off by one | Medium | Signature validation fails | Comprehensive unit tests with boundary checks |
| Stub signature length mismatch | Low | Gas estimation fails | Add unit test to verify stub length |
| Existing sessions become invalid | High | User experience issue | Expected and acceptable; sessions were already broken |
