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

## Monorepo structure

```
apps/
  web/          → Next.js 15 frontend
  indexer/      → Rust Axum backend
packages/
  contracts/    → Solidity smart contracts (Foundry)
  shared-types/ → TypeScript types from contract ABIs
```
