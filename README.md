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
| PerpEngine | `0xe35486669A5D905CF18D4af477Aaac08dF93Eab0` |
| Settlement | `0x24354D1022E13f39f330Bbf2210edEEd21422eD5` |
| PriceOracle | `0x7FBe2a83113A6374964d6fe25C000402471079d4` |
| MockUSDC | `0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB` |
| MockPriceFeed | `0xd152AaBf6e4dA27004dC4a4B29da4a7754318469` |
| SessionKeyValidator | `0x672B55126649951AfbbD13d82015691BC8BAD007` |
| VerifyingPaymaster | `0xbcB4B1FdEC3958BEAc5542B4752f7FAf4BcaF226` |

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
