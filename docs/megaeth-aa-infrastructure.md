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
Browser (permissionless + @zerodev/sdk + @zerodev/passkey-validator)
    │
    │  eth_sendUserOperation
    ▼
Alto bundler :4337
    │
    │  handleOps() — legacy tx
    ▼
EntryPoint v0.7 → MegaETH Carrot
```

**The Rust indexer is read-only** — prices, positions, on-chain events only.
Transactions go directly from the browser to Alto. There is no relay endpoint.

**Why not ZeroDev SDK directly?**
ZeroDev's client calls `zd_getUserOperationGasPrice` which Alto does not implement.
Use `createSmartAccountClient` from `permissionless` and override `estimateFeesPerGas`
to call Alto's `pimlico_getUserOperationGasPrice`. See the code snippet below.

**Required packages:**
```bash
pnpm add @zerodev/sdk @zerodev/passkey-validator permissionless viem tslib
```

**Gas price override (required for Alto compatibility):**
```typescript
import { createSmartAccountClient } from "permissionless";
import { http } from "viem";

const smartAccountClient = createSmartAccountClient({
  account: kernelAccount,
  chain: megaEthCarrot,
  bundlerTransport: http(process.env.NEXT_PUBLIC_BUNDLER_RPC_URL),
  userOperation: {
    estimateFeesPerGas: async () => {
      const res = await fetch(process.env.NEXT_PUBLIC_BUNDLER_RPC_URL!, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "pimlico_getUserOperationGasPrice",
          params: [],
        }),
      }).then((r) => r.json());
      const { maxFeePerGas, maxPriorityFeePerGas } = res.result.standard;
      return {
        maxFeePerGas: BigInt(maxFeePerGas),
        maxPriorityFeePerGas: BigInt(maxPriorityFeePerGas),
      };
    },
  },
});
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
| EntryPointSimulations v0.7 | `0x097219E615B5042095A707797fc30d67DbD58045` |
| PimlicoSimulations | `0xf64BddD711a41aA281a00Ff5D90aa0aB59014402` |
| SessionKeyValidator | `0x672B55126649951AfbbD13d82015691BC8BAD007` |
| VerifyingPaymaster | `0xbcB4B1FdEC3958BEAc5542B4752f7FAf4BcaF226` |

### Core Protocol

| Contract | Address |
|----------|---------|
| PerpEngine | `0xe35486669A5D905CF18D4af477Aaac08dF93Eab0` |
| Settlement | `0x24354D1022E13f39f330Bbf2210edEEd21422eD5` |
| PriceOracle | `0x7FBe2a83113A6374964d6fe25C000402471079d4` |
| MockUSDC | `0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB` |
| MockPriceFeed | `0xd152AaBf6e4dA27004dC4a4B29da4a7754318469` |

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
    │       → concat([sessionKeyAddress (20 bytes), ecdsaSign(userOpHash) (65 bytes)])
    │       → NO wallet popup
    │
    └─ 6. submitUserOp(signedOp)
            → eth_sendUserOperation → Alto :4337 → EntryPoint v0.7 → MegaETH
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
1. Approved PerpEngine to spend USDC (`ERC20.approve(PerpEngine, amount)`)
2. Granted a session key via `SessionKeyValidator.grantSession(...)` (done by `DelegateModal`)
