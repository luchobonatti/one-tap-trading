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

External bundler required. Pimlico does NOT support chain 6343.

Recommended next steps:
- Check Alchemy Bundler for chain 6343 support
- Check Stackup for chain 6343 support
- As fallback: self-hosted bundler (eth-infinitism reference implementation)

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
| PerpEngine | `0xe35486669A5D905CF18D4af477Aaac08dF93Eab0` |
| Settlement | `0x24354D1022E13f39f330Bbf2210edEEd21422eD5` |
| PriceOracle | `0x7FBe2a83113A6374964d6fe25C000402471079d4` |
| MockUSDC | `0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB` |
