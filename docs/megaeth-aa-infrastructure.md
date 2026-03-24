# MegaETH Carrot — AA Infrastructure

Chain ID: 6343 | RPC: https://carrot.megaeth.com/rpc

## EntryPoint

| Version | Address | Status |
|---------|---------|--------|
| v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | ✅ Deployed |
| v0.6 | `0x5FF137D4b0FDCD49DcA30c7CF7f08a6C83Cff3a6` | ❌ Not deployed |

Use EntryPoint v0.7. Import via `account-abstraction/interfaces/IEntryPoint.sol`.

## Bundler

`eth_sendUserOperation` is NOT supported on the MegaETH native RPC.
Pimlico does NOT support chain 6343. We self-host **Alto** (Pimlico's open-source bundler).

**Setup:** See `tools/alto/README.md` for full instructions.
**Config:** `tools/alto/megaeth-carrot.json` (committed to repo).

### Key MegaETH flags for Alto

```bash
node alto/src/esm/cli/index.js \
  --config tools/alto/megaeth-carrot.json \
  --executor-private-keys "$DEPLOYER_PRIVATE_KEY" \
  --utility-private-key "$DEPLOYER_PRIVATE_KEY"
```

### Alto simulation contracts (pre-deployed on Carrot)

Alto requires simulation contracts for gas estimation. These cannot be deployed
automatically by Alto because MegaETH requires `--legacy` transactions.
**They are already deployed — do not redeploy.**

| Contract | Address |
|----------|---------|
| EntryPointSimulations v0.7 | `0x097219E615B5042095A707797fc30d67DbD58045` |
| PimlicoSimulations | `0xf64BddD711a41aA281a00Ff5D90aa0aB59014402` |

### POC verified

Full end-to-end test passed on Carrot:
- ZeroDev Kernel v3 account created and funded
- UserOp submitted → confirmed in one block (~10ms)
- Bundle tx: `0xc3b3bc65eb390b8584b08fed46a4112d892d4401f106495438af367391e950c6`

### Frontend stack (no backend involvement)

```
Frontend → Alto (port 4337) → EntryPoint v0.7 → MegaETH
```

The Rust indexer is read-only. Transactions never go through the backend.

Packages: `@zerodev/sdk`, `@zerodev/ecdsa-validator`, `permissionless`, `viem`, `tslib`

## RIP-7212 (P256 Precompile)

The P256 precompile at `0x0000000000000000000000000000000000000100` is **NOT deployed** on Carrot.

Impact: Passkey (WebAuthn) signature verification costs ~200k gas (software P256.sol) instead of ~3.5k gas.
This is acceptable for testnet; re-evaluate for mainnet.

Session keys use ECDSA (secp256k1) which is unaffected by this.

## EIP-7966 (eth_sendRawTransactionSync)

Not supported on Carrot. Use standard `eth_sendRawTransaction` (async).

Frontend must poll for transaction receipts or use the bundler's `eth_getUserOperationReceipt`.

## Contract Addresses

| Contract | Address |
|----------|---------|
| EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |
| EntryPointSimulations v0.7 | `0x097219E615B5042095A707797fc30d67DbD58045` |
| PimlicoSimulations | `0xf64BddD711a41aA281a00Ff5D90aa0aB59014402` |
| PerpEngine | `0xe35486669A5D905CF18D4af477Aaac08dF93Eab0` |
| Settlement | `0x24354D1022E13f39f330Bbf2210edEEd21422eD5` |
| PriceOracle | `0x7FBe2a83113A6374964d6fe25C000402471079d4` |
| MockUSDC | `0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB` |
