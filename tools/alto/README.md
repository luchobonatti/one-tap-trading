# Alto Bundler — MegaETH Carrot Setup

Self-hosted [Alto](https://github.com/pimlicolabs/alto) bundler for MegaETH Carrot testnet (chain 6343).
Pimlico does not support chain 6343, so we self-host.

## Architecture

```
Frontend → Alto (port 4337) → EntryPoint v0.7 → MegaETH
Indexer  → read-only (prices, positions, events)
```

The backend (Rust indexer) never touches transactions. The frontend submits
UserOps directly to Alto, which bundles and submits to EntryPoint.

## Pre-deployed contracts (Carrot testnet)

| Contract | Address |
|----------|---------|
| EntryPointSimulations v0.7 | `0x097219E615B5042095A707797fc30d67DbD58045` |
| PimlicoSimulations | `0xf64BddD711a41aA281a00Ff5D90aa0aB59014402` |
| EntryPoint v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |

These simulation contracts were pre-deployed with forge because Alto cannot
deploy them automatically — MegaETH's gas model requires `--legacy` and
`--gas-estimate-multiplier 5000` (see `docs/gotchas.md`).

## Setup

```bash
# 1. Clone Alto (one-time)
git clone https://github.com/pimlicolabs/alto /tools/alto
cd /tools/alto && pnpm install && pnpm build:all

# 2. Copy your .env (already done if you ran pnpm setup from repo root)
# DEPLOYER_PRIVATE_KEY must be in your root .env

# 3. Run
source .env
node /tools/alto/src/esm/cli/index.js \
  --config /path/to/one-tap-trading/tools/alto/megaeth-carrot.json \
  --executor-private-keys "$DEPLOYER_PRIVATE_KEY" \
  --utility-private-key "$DEPLOYER_PRIVATE_KEY"
```

## MegaETH-specific config explained

| Flag | Value | Why |
|------|-------|-----|
| `--safe-mode false` | false | MegaETH has no `debug_traceCall` |
| `--chain-type op-stack` | op-stack | MegaETH is OP-stack based |
| `--legacy-transactions` | true | MegaETH requires legacy (type 0) txs |
| `--block-time` | 10 | MegaETH has 10ms blocks |
| `--transaction-gas-stipend` | 60000 | MegaETH base intrinsic is 60k (not 21k) |
| `--max-gas-per-user-op` | 300M | MegaETH gas costs are ~30x mainnet |
| `--v7-*-multiplier` | 500 | 5x buffer for MegaETH gas estimation |
| `--deploy-simulations-contract` | false | Pre-deployed manually (see above) |

## Frontend integration

```typescript
import { createSmartAccountClient } from "permissionless";

const smartAccountClient = createSmartAccountClient({
  account: kernelAccount,
  chain: megaEthCarrot,
  bundlerTransport: http(process.env.NEXT_PUBLIC_BUNDLER_RPC_URL),
  userOperation: {
    estimateFeesPerGas: async () => {
      // Alto exposes pimlico_getUserOperationGasPrice
      const res = await fetch(process.env.NEXT_PUBLIC_BUNDLER_RPC_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0", id: 1,
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

## Packages

```bash
pnpm add @zerodev/sdk @zerodev/ecdsa-validator permissionless viem tslib
```

## POC verified

Full stack tested and working:
- ZeroDev Kernel v3 account (`0x443cdE3fBF9EbAEd2e44F707164e2d9bBB4BD16a`)
- UserOp hash: `0x2baaa836c0a0329fa0abf552c073265379bebb467fedc3b8e6eb3158d1e439de`
- Bundle tx: `0xc3b3bc65eb390b8584b08fed46a4112d892d4401f106495438af367391e950c6`
