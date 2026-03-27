# Gotchas & Discoveries

Running log of non-obvious findings that burned time. Read this before touching anything for the first time.

---

## MegaETH Carrot Testnet

**Chain ID is 6343, not 6342.**

**Gas model is ~30x mainnet.** A simple 2.9 KB ERC20 deploy costs ~25 M gas on Carrot vs ~300 K on mainnet. Foundry's local simulation is blind to this — it estimates normal EVM costs and the broadcast fails with `intrinsic gas too low`.

Required flags for any `forge script --broadcast` on Carrot:

```bash
forge script script/... \
  --rpc-url $MEGAETH_RPC_URL \
  --broadcast \
  --legacy \
  --gas-estimate-multiplier 5000
```

`foundry.toml` has a `[profile.megaeth]` with `gas_estimate_multiplier = 5000` for reference.
Use `cast estimate --rpc-url $MEGAETH_RPC_URL ...` to get the real on-chain gas cost before broadcasting.

---

## Account Abstraction (ERC-4337)

**EntryPoint v0.7 deployed at `0x0000000071727De22E5E9d8BAf0edAc6f37da032` on Carrot.**
EntryPoint v0.6 is not deployed. Use v0.7 for all AA interactions.

**RIP-7212 P256 precompile not available on Carrot.**
Passkey (WebAuthn) signature verification requires a software P256.sol verifier (~200k gas) instead of the precompile (~3.5k gas). Session keys use ECDSA (secp256k1) and are unaffected.

**EIP-7966 not available on Carrot.**
`eth_sendRawTransactionSync` is not supported. Use standard async `eth_sendRawTransaction` and poll for receipts.

**No native ERC-4337 bundler on MegaETH RPC — use ZeroDev hosted.**
`eth_sendUserOperation` is not natively supported on the MegaETH RPC. Use the ZeroDev
hosted bundler (v3 API, supports chain 6343). Create a project at
[dashboard.zerodev.app](https://dashboard.zerodev.app) and set `NEXT_PUBLIC_BUNDLER_RPC_URL`
in `.env`. No local process needed — `pnpm dev` is enough.

Full details: [`docs/megaeth-aa-infrastructure.md`](megaeth-aa-infrastructure.md)

**Chain ID confusion: ZeroDev dashboard lists 6342, actual chain is 6343.**
Both refer to the same Carrot testnet — ethereum-lists had the wrong ID. viem's
`megaethTestnet` definition already uses 6343. ZeroDev's v3 bundler routes correctly
to chain 6343 regardless of what the dashboard label says.

---

## Foundry

**`vm.writeFile` requires explicit `fs_permissions`.**
Add this to `foundry.toml` or the script will silently fail:

```toml
fs_permissions = [{ access = "read-write", path = "deployments" }]
```

**`vm.prank` is consumed by the very next call — including view calls.**
If you write `vm.prank(alice); vm.expectRevert(...); contract.foo()` and `foo` is a view, prank is consumed by the revert check, not `foo`. Order matters.

**`forge fmt` runs automatically via prek pre-commit hooks.**
The first commit will always fail (formatter runs, modifies files, hook aborts). Re-stage the formatted files and commit again. This is expected — not a bug.

**Fuzz exit price ranges must be proportional to entry price.**
If exit price can be orders of magnitude above entry, the solvency invariant breaks in unrealistic ways. Bound fuzz ranges relative to entry (e.g. `[entry/2, entry*2]`).

**`[fuzz]` and `[invariant]` sections in `foundry.toml` set run counts globally.**
`runs = 10_000` applies to all fuzz tests. Override per-test with `/// forge-config: default.fuzz.runs = N`.

**`broadcast/` must be gitignored.**
Foundry writes nonces, gas estimates, and raw tx data there. It is not deployment state — `deployments/{chainId}.json` is.

---

## Contract Architecture

**Settlement is deployed in two steps.**
Constructor takes `engine = address(0)`. After PerpEngine is deployed, call `settlement.setEngine(address(engine))`. The deploy script handles this automatically — don't skip step 6.

**Struct packing order controls storage slots.**
Solidity packs fields in declaration order. `address` (20 B) + `uint8` (1 B) + `uint40` (5 B) + `bool` (1 B) + `bool` (1 B) = 28 B → fits in one 32 B slot. Put `uint256` / `uint128` fields after the packed cluster or they force a new slot. `uint128 collateral` + `uint128 unrealisedPnl` = exactly 32 B = one slot.

---

## Environment

**Single `.env` at the repo root — one source of truth.**
Run `pnpm setup` once after cloning to symlink `packages/contracts/.env → ../../.env`.
Foundry reads `packages/contracts/.env` on `forge script`; the symlink makes it read the root file transparently.

**`DEPLOYER_PRIVATE_KEY` must have the `0x` prefix.**
`vm.envUint` rejects bare hex strings. Format: `DEPLOYER_PRIVATE_KEY=0xabc123...`

---

## Rust / Indexer

**`clippy::exit` does not fire for `std::process::exit(1)` in rustc/clippy 1.93.1.**
The lint is configured in `Cargo.toml` but the compiler does not enforce it at that version. Do not rely on this lint as a guardrail — review exit calls manually.

---

## Auth / Session Keys

**DataRunnerPage introduced a wrong digest formula and wrong nonce during the perps migration.**
The correct signing flow lives in the pre-existing passkey pipeline. Any new page that sends transactions must go through that pipeline, not re-implement signing. See the `bugfix: passkey/session-key pipeline` commit for details.
