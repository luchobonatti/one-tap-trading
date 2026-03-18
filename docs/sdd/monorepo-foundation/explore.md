# Explore: monorepo-foundation

> **Change**: monorepo-foundation
> **Status**: Complete
> **Date**: 2026-03-18

## Summary

Investigation of what's needed to set up the monorepo foundation for a greenfield gamified trading web app on MegaETH (Phase 0 of the roadmap).

## Findings

### 7 Areas Required

| # | Area | Complexity | Description |
|---|------|-----------|-------------|
| 1 | Turborepo config | Medium | Mixed TS/Rust/Solidity task pipeline with caching |
| 2 | Frontend scaffold | Low | Next.js 15 + React 19 + Tailwind v4 |
| 3 | Backend scaffold | Medium | Axum server with Tokio runtime |
| 4 | Contracts scaffold | Low-Medium | Foundry project with remappings |
| 5 | Shared types pipeline | Medium | wagmi CLI: ABI → TypeScript on build |
| 6 | CI/CD | Medium | GitHub Actions for lint, typecheck, test, build |
| 7 | Pre-commit hooks | Low | prek for local quality gates |

### Critical Dependency Chain

```
Contracts (Foundry)
    |
    v
Shared Types (wagmi CLI)
    |
    v
Frontend (Next.js) + Backend (Axum)   [parallel]
    |
    v
CI/CD (GitHub Actions)
```

### Turborepo

- Root `turbo.json` with task pipeline for mixed TS/Rust/Solidity
- Cache invalidation strategy needed for Cargo.lock and foundry.lock
- Task ordering: `contracts:build` → `shared-types:generate` → `web:build` / `indexer:build`
- Rust and Foundry tasks need custom cache keys (not just file hashes)

### Frontend (Next.js 15)

- Straightforward scaffold: `create-next-app` with TypeScript strict, Tailwind v4, App Router
- Canvas 2D is standard browser API — no special setup needed in Phase 0
- Strict tsconfig: `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`
- Testing: Vitest
- Linting: oxlint

### Backend (Rust Axum)

- Cargo workspace within pnpm monorepo (Turborepo delegates to cargo)
- Axum server with Tokio runtime, basic middleware (CORS, logging)
- Health check endpoint (`GET /health`) only for Phase 0
- Cargo.toml with clippy pedantic lints
- Dev profile optimized for compile speed, release for performance

### Contracts (Foundry)

- `foundry.toml` with solc 0.8.28+, optimizer enabled, remappings
- Basic contract skeleton (e.g. `PerpEngine.sol` stub)
- Test structure mirroring src/
- ABI output configured for wagmi CLI consumption

### Shared Types (wagmi CLI)

- `wagmi.config.ts` pointing to Foundry ABI output directory
- Generates TypeScript types + React hooks from contract ABIs
- Must run AFTER `forge build` (Turborepo dependency)
- Types NOT committed — generated on build (locally and in CI)

### CI/CD

- GitHub Actions: parallel jobs for lint, typecheck, test
- Caching: pnpm store, Cargo registry, Foundry binaries
- Status checks required for PR merge
- Toolchain setup: Node 22, Rust stable, Foundry

### Pre-commit Hooks

- prek (Rust-based, fast) — replaces pre-commit (Python)
- Hooks: oxlint, cargo clippy, cargo fmt, forge fmt
- Auto-fix where possible

## Effort Estimate

- **Total**: 3-4 days (single developer)
- **Parallelizable**: 2 days with 2 devs (frontend + backend can scaffold in parallel)

## Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Turborepo cache with mixed languages | Medium | Test cache invalidation early |
| wagmi CLI silent failures | Medium | Explicit error handling in build scripts |
| Rust compilation time | Medium | Incremental builds, separate dev/release profiles |
| Environment variable sprawl | Low | Centralized `.env` strategy |

## Design Decisions Made

1. wagmi-generated types NOT committed — generated in CI and locally on build
2. In-memory storage only for Phase 0 — no database
3. Root `.env.example` with per-workspace startup validation
4. All commands from root (`pnpm dev`, `pnpm test`, `pnpm build`)
5. ETH/USD as initial asset (affects contract skeleton naming)

## Open Questions (Resolved)

| Question | Decision |
|----------|---------|
| Commit generated types? | No — generate in CI and locally |
| Database in Phase 0? | No — in-memory only |
| Indexer language? | Rust (Axum + Tokio) |
| Env var strategy? | Root `.env.example`, per-workspace validation |
| Command surface? | All from root via Turborepo |
| Deployment? | Deferred — not in Phase 0 scope |
