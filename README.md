# One Tap Trading

Gamified, mobile-first trading web app on MegaETH.

## Quick start

```bash
git clone --recurse-submodules https://github.com/luchobonatti/one-tap-trading.git
cd one-tap-trading
pnpm install
pnpm build
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

## Commands

| Command | Description |
|---------|-------------|
| `pnpm dev` | Start all workspaces in dev mode |
| `pnpm build` | Build all workspaces |
| `pnpm test` | Run all tests (vitest + cargo test + forge test) |
| `pnpm lint` | Lint all workspaces |
| `pnpm typecheck` | Type-check TypeScript workspaces |
| `pnpm format` | Format all workspaces |
| `pnpm clean` | Clean build artifacts |

## Deployed contracts

MegaETH Carrot testnet (chain ID 6343):

| Contract | Address |
|----------|---------|
| PerpEngine | `0x3b94b364697714620c4596e1c51e5b24a0964204` |
| Settlement | `0x24354d1022e13f39f330bbf2210edeed21422ed5` |
| PriceOracle | `0xf5e08914893f87f687f6f39799c32ed2210f410a` |
| RedStoneAdapter | `0x3812e928c1d55de3707c93d8bc74026a3249134d` |
| MockUSDC | `0xbd2e92b39081a9dc541a776b5d7b7e0051851ccb` |
| SessionKeyValidator | `0xb5ea8abff1bd18ceb9ee5b40a55d832bbb5d1b44` |
| VerifyingPaymaster | `0xe13998047b0b13ad9df7672e28bc4b5ceaa00c35` |

Full deployment artifact: [`packages/contracts/deployments/6343.json`](packages/contracts/deployments/6343.json)

## Monorepo structure

```
apps/
  web/          → Next.js 15 frontend
  indexer/      → Rust Axum backend
packages/
  contracts/    → Solidity smart contracts (Foundry)
  shared-types/ → TypeScript types from contract ABIs
```
