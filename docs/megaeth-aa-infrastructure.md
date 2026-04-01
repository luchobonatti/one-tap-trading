# MegaETH Carrot — AA Infrastructure

Chain ID: 6343 | RPC: https://carrot.megaeth.com/rpc

## EntryPoint

| Version | Address | Status |
|---------|---------|--------|
| v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | ✅ Deployed |
| v0.6 | `0x5FF137D4b0FDCD49DcA30c7CF7f08a6C83Cff3a6` | ❌ Not deployed |

Use EntryPoint v0.7. The `account-abstraction` library is a git submodule under
`packages/contracts/lib/`. Run `git submodule update --init` after cloning, then import:
`account-abstraction/interfaces/IEntryPoint.sol`.

## Bundler

`eth_sendUserOperation` is NOT supported on the MegaETH native RPC.
We use **ZeroDev's hosted bundler** (v3 API), which supports chain 6343.

**Setup:** Create a project at [dashboard.zerodev.app](https://dashboard.zerodev.app),
select "MegaETH Testnet", and copy the bundler URL into `.env`.

```bash
BUNDLER_RPC_URL=https://rpc.zerodev.app/api/v3/{PROJECT_ID}/chain/6343
NEXT_PUBLIC_BUNDLER_RPC_URL=https://rpc.zerodev.app/api/v3/{PROJECT_ID}/chain/6343
```

No local bundler process required. `pnpm dev` is enough.

### Frontend stack (no backend involvement)

```mermaid
graph LR
  A[Browser<br/>permissionless + @zerodev/sdk] -->|eth_sendUserOperation| B[ZeroDev Bundler<br/>hosted]
  B -->|handleOps — legacy tx| C[EntryPoint v0.7<br/>MegaETH Carrot]
```

**The Rust indexer is read-only** — prices, positions, on-chain events only.
Transactions go directly from the browser to the ZeroDev bundler.

**Required packages:**
```bash
pnpm add @zerodev/sdk @zerodev/passkey-validator permissionless viem tslib
```

## RIP-7212 (P256 Precompile)

The P256 precompile at `0x0000000000000000000000000000000000000100` is **NOT deployed** on Carrot.

Impact: Passkey (WebAuthn) signature verification costs ~200k gas (software P256.sol) instead of ~3.5k gas.
This is acceptable for testnet; re-evaluate for mainnet.

Session keys use ECDSA (secp256k1) which is unaffected by this.

## EIP-7966 (eth_sendRawTransactionSync)

Not supported on Carrot. Use standard `eth_sendRawTransaction` (async).

Frontend must poll for transaction receipts or use the bundler's `eth_getUserOperationReceipt`.

## Contract Addresses

Full artifact: [`packages/contracts/deployments/6343.json`](../packages/contracts/deployments/6343.json)

### AA Infrastructure

| Contract | Address |
|----------|---------|
| EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |
| SessionKeyValidator | `0xb5ea8abff1bd18ceb9ee5b40a55d832bbb5d1b44` |
| VerifyingPaymaster | `0xe13998047b0b13ad9df7672e28bc4b5ceaa00c35` |

### Core Protocol

| Contract | Address |
|----------|---------|
| PerpEngine | `0x3b94b364697714620c4596e1c51e5b24a0964204` |
| Settlement | `0x24354d1022e13f39f330bbf2210edeed21422ed5` |
| PriceOracle | `0xf5e08914893f87f687f6f39799c32ed2210f410a` |
| RedStoneAdapter | `0x3812e928c1d55de3707c93d8bc74026a3249134d` |
| MockUSDC | `0xbd2e92b39081a9dc541a776b5d7b7e0051851ccb` |

Note: `MockPriceFeed` (`0x85f5dc082ca674f5421fe93e106022a2a1ba1a30`) remains deployed but is deprecated — replaced by `RedStoneAdapter` in Phase 2j.

---

## Trading Flow (end-to-end)

Full flow from grid tap to confirmed on-chain position — zero wallet popups after the initial session key delegation.

```
User taps grid cell
    │
    ▼
lib/trading/submit.ts — openTrade({ isLong, collateral, leverage, accountAddress })
    │
    ├─ 1. getCurrentPriceBounds() — reads PriceOracle.getPrice()
    │       builds: { expectedPrice, maxDeviation: 2%, deadline: now+60s }
    │
    ├─ 2. encodeFunctionData(perpEngineAbi, "openPosition", [...])
    │
    ├─ 3. buildKernelCallData(PerpEngine, innerCallData)
    │       → Kernel execute(mode=0x00, encodePacked(target, 0, data))
    │
    ├─ 4. buildUserOp(smartAccountAddress, kernelCallData)
    │       → nonce key = BigInt(SessionKeyValidator) → routes to our validator
    │       → paymaster = VerifyingPaymaster (sponsors gas)
    │
    ├─ 5. signUserOp(userOp, session)
    │       → mode(1B 0x01) + validatorAddr(20B) + sessionKeyAddr(20B) + ecdsaSig(65B) = 106 bytes
    │       → NO wallet popup
    │
    └─ 6. submitUserOp(signedOp)
            → eth_sendUserOperation → ZeroDev bundler → EntryPoint v0.7 → MegaETH
```

### PriceBounds struct

```solidity
struct PriceBounds {
    uint256 expectedPrice;  // from PriceOracle.getPrice()
    uint256 maxDeviation;   // 2% of expectedPrice (200 BPS)
    uint256 deadline;       // block.timestamp + 60s
}
```

### Contract constants

| Constant | Value | Notes |
|----------|-------|-------|
| `MIN_COLLATERAL` | `1e6` | 1 USDC minimum per position |
| `MAX_LEVERAGE` | `100` | Absolute cap |
| `MAX_SAFE_LEVERAGE` | `20` | Safe cap (not immediately liquidatable) |

### Session key prerequisites

Before any trade, the smart account must have:
1. Approved USDC spending (`ERC20.approve(spender, amount)`) — **Note:** Settlement is who
   calls `safeTransferFrom`, but the VerifyingPaymaster currently enforces `spender == PerpEngine`.
   This is a known mismatch that requires a Paymaster contract update to fix (see `docs/gotchas.md`).
2. Granted a session key via `SessionKeyValidator.grantSession(...)` (done by `DelegateModal`)
