# Agent Configuration — One Tap Trading

> `CLAUDE.md` is symlinked to this file so Claude Code picks it up automatically. Other agents (Cursor, Windsurf, etc.) read `AGENTS.md` natively.

---

## Product Context

One Tap Trading is a gamified, mobile-first trading web app on MegaETH. Users tap a grid square overlaid on a real-time price chart to open leveraged perpetual futures positions fully on-chain. Zero wallet popups, zero forms, zero financial knowledge required.

## Stack & Conventions

### Frontend (`apps/web/`)

- **Framework:** Next.js 15 (App Router) + React 19
- **Styling:** Tailwind CSS v4
- **Rendering:** Canvas 2D for real-time chart (bypasses React state), React DOM for UI shell
- **Types:** Strict TypeScript — `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`
- **Linting:** oxlint (typescript, import, unicorn plugins)
- **Formatting:** oxfmt
- **Testing:** Vitest + React Testing Library
- **Naming:** camelCase for variables/functions, PascalCase for components/types, kebab-case for files

### Backend / Indexer (`apps/indexer/`)

- **Language:** Rust (2021 edition)
- **Framework:** Axum 0.7 + Tokio (multi-threaded runtime)
- **Middleware:** tower-http (CORS, logging, compression)
- **Linting:** clippy pedantic with panic prevention lints (see Cargo.toml)
- **Formatting:** cargo fmt
- **Testing:** cargo test

### Smart Contracts (`packages/contracts/`)

- **Language:** Solidity 0.8.28+
- **Framework:** Foundry (forge, cast, anvil)
- **Testing:** forge test with fuzz testing (10k+ runs for critical paths)
- **Formatting:** forge fmt

### Shared Types (`packages/shared-types/`)

- **Generator:** wagmi CLI — reads Foundry ABI output, generates TypeScript types
- **Policy:** Generated types are NEVER committed — regenerated on build

### Monorepo

- **Package manager:** pnpm (workspaces)
- **Build orchestration:** Turborepo
- **Dependency chain:** `contracts:build` → `shared-types:generate` → `web:build` + `indexer:build`

## Architecture

```
apps/
  web/                → Next.js 15 frontend (user-facing trading interface)
  indexer/            → Rust Axum backend (blockchain indexing, WebSocket price relay, leaderboard API)
packages/
  contracts/          → Solidity smart contracts (PerpEngine, SessionKeyValidator, Paymaster)
  shared-types/       → TypeScript types generated from contract ABIs
docs/
  sdd/                → Spec-Driven Development artifacts
```

### Key Integration Points

- Frontend imports types from `@one-tap/shared-types` (workspace dependency)
- Frontend connects to indexer via WebSocket for real-time price data
- Frontend sends transactions to MegaETH via `eth_sendRawTransactionSync` (EIP-7966)
- Indexer subscribes to MegaETH events via `alloy` and serves REST + WebSocket APIs
- Contracts interact with RedStone Bolt oracle for price feeds

### Blockchain

- **Network:** MegaETH (EVM L2, 10ms blocks)
- **Testnet:** Carrot (chain ID 6342)
- **Oracle:** RedStone Bolt (2.4ms push oracle)
- **Account Abstraction:** ERC-4337 smart wallets + Session Keys

## Testing

- **Framework (TS):** Vitest + React Testing Library
- **Framework (Rust):** cargo test
- **Framework (Solidity):** Foundry forge test + fuzz
- **Run all tests:** `pnpm test`
- **What to test:** Business logic, contract invariants, API endpoints, component behavior
- **What not to test:** Styling, third-party library internals, trivial getters
- **Contracts:** Fuzz test all public functions. Invariant: `total_payouts <= total_collateral + house_reserve`
- **Coverage:** Cover the paths that matter. Every error path the code handles should have a test.

## Commit Standards

Follow the [7 Rules of a Great Commit Message](https://cbea.ms/git-commit/):

1. Separate subject from body with a blank line
2. Limit the subject line to 50 characters
3. Capitalize the subject line
4. Do not end the subject line with a period
5. Use the imperative mood in the subject line
6. Wrap the body at 72 characters
7. Use the body to explain *what* and *why*, not *how*

## PR Workflow

- Every PR must reference an issue (`Closes #N`)
- Mirror the issue's acceptance criteria in the PR
- Self-review your diff before requesting peer review
- Keep PRs small and focused — one issue, one PR
- Use the PR template at `.github/PULL_REQUEST_TEMPLATE.md`

## Diagrams

- NEVER use ASCII art for diagrams
- ALWAYS use Mermaid syntax (```mermaid blocks)

## Guardrails

- Do not commit secrets, API keys, or credentials — use `.env` files (gitignored)
- Do not modify CI/CD pipelines without team review
- Do not skip tests or linting to make a build pass
- Do not commit generated types (`packages/shared-types/generated/`)
- When in doubt, ask — don't assume
