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
- **Framework:** Axum 0.8 + Tokio (multi-threaded runtime)
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
- **Testnet:** Carrot (chain ID 6343)
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

## Known Gotchas

Non-obvious findings that have burned time before. Full details in [`docs/gotchas.md`](docs/gotchas.md).

- **MegaETH gas is ~30x mainnet** — always use `--legacy --gas-estimate-multiplier 5000` when broadcasting
- **Chain ID is 6343** (not 6342)
- **`forge fmt` runs on pre-commit** — first commit always fails; re-stage and recommit
- **`vm.prank` is consumed by the next call** including view calls inside `expectRevert`
- **Settlement deploys in two steps** — constructor takes `engine=address(0)`, wire after PerpEngine deploy
- **`pnpm setup`** creates `packages/contracts/.env → ../../.env` symlink (run once after clone)
- **`DEPLOYER_PRIVATE_KEY` needs `0x` prefix** — `vm.envUint` rejects bare hex
- **EntryPoint v0.7** deployed at `0x0000000071727De22E5E9d8BAf0edAc6f37da032` on Carrot
- **RIP-7212 P256 precompile not available** on Carrot — passkeys use software verifier (~200k gas)
- **EIP-7966 not available** on Carrot — use standard async `eth_sendRawTransaction`
- **No native ERC-4337 bundler** on MegaETH RPC — self-host Alto with `tools/alto/megaeth-carrot.json` (POC verified)
- **Alto cannot auto-deploy simulation contracts** on MegaETH — pre-deployed manually, pass `--deploy-simulations-contract false`
- **ZeroDev SDK `zd_getUserOperationGasPrice`** not supported by Alto — use `permissionless` + `pimlico_getUserOperationGasPrice`
