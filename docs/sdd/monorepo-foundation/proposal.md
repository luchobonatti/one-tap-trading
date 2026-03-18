# Proposal: monorepo-foundation

> **Change**: monorepo-foundation
> **Status**: Approved
> **Date**: 2026-03-18

## Intent

Establish the foundational monorepo infrastructure for One Tap Trading — a gamified trading web app on MegaETH. This change unblocks ALL subsequent development phases. Without it, no feature work can begin.

The goal: any developer runs `pnpm dev` and has frontend + backend + contracts compiling.

## Scope

### In Scope

1. **Monorepo structure**: pnpm workspaces + Turborepo with task pipeline for mixed TS/Rust/Solidity
2. **Frontend scaffold**: Next.js 15 + React 19 + Tailwind v4 + strict tsconfig — landing page placeholder
3. **Backend scaffold**: Rust Axum + Tokio workspace — health check endpoint only
4. **Contracts scaffold**: Foundry project — foundry.toml, basic contract skeleton, forge test passing
5. **Shared types pipeline**: wagmi CLI generates TypeScript types from contract ABIs on build
6. **CI/CD**: GitHub Actions — lint + typecheck + forge test + cargo test on every PR
7. **Pre-commit hooks**: prek for format + lint before each commit
8. **Dev experience**: `pnpm dev` starts all workspaces, `pnpm build` builds everything

### Out of Scope (deferred to later phases)

- Database / persistence (in-memory only)
- Authentication / Account Abstraction / Session Keys
- Business logic (trading engine, pricing, positions)
- Canvas rendering / real-time chart
- WebSocket infrastructure
- Oracle integration (RedStone Bolt)
- Deployment infrastructure (Vercel, fly.io)
- Smart contract logic beyond skeleton

## Approach

| Step | Action | Output |
|------|--------|--------|
| 1 | Initialize pnpm workspace + turbo.json | Root monorepo config |
| 2 | Scaffold `apps/web/` | Next.js 15 + React 19 + Tailwind v4 app |
| 3 | Scaffold `apps/indexer/` | Rust Axum workspace with health endpoint |
| 4 | Scaffold `packages/contracts/` | Foundry project with basic contract + test |
| 5 | Set up `packages/shared-types/` | wagmi CLI pipeline (ABI → TS types) |
| 6 | Wire Turborepo dependencies | contracts:build → shared-types:generate → web:build |
| 7 | Add GitHub Actions CI | lint + typecheck + test on PR |
| 8 | Configure prek hooks | Pre-commit format + lint |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Type generation | Generated in CI, NOT committed | Types are derived artifacts — committing creates sync issues |
| Storage | In-memory only | No DB complexity in Phase 0 — add in Phase 4 |
| Env vars | Root `.env.example` | Per-workspace validation at startup |
| Commands | All from root | `pnpm dev/test/build/lint` — Turborepo orchestrates |
| Initial asset | ETH/USD | Native liquidity on MegaETH, single oracle feed |

## Success Criteria

- [ ] `pnpm install` succeeds
- [ ] `pnpm dev` starts web + indexer concurrently
- [ ] `pnpm build` builds all workspaces with Turborepo caching
- [ ] `pnpm lint` passes (oxlint + clippy + forge fmt)
- [ ] `pnpm typecheck` passes (tsc --noEmit)
- [ ] `pnpm test` runs vitest + cargo test + forge test
- [ ] CI green on PR to main
- [ ] Pre-commit hooks prevent broken commits
- [ ] Build time < 30s (cached)

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Turborepo cache invalidation with Rust/Foundry | Medium | Medium | Test cache behavior early, custom cache keys |
| pnpm workspace dependency conflicts | Medium | Low | Strict workspace protocol, catalog for shared deps |
| wagmi CLI silent failures in pipeline | Medium | Medium | Explicit error handling in build scripts |
| Rust compilation time slowing dev loop | Low | Medium | Incremental builds, dev profile optimizations |

## Effort Estimate

- **Single developer**: 3-4 days
- **Two developers**: 2 days (frontend + backend scaffold in parallel)

## Dependency Chain

```
Contracts (Foundry)
    → Shared Types (wagmi CLI)
        → Frontend (Next.js) + Backend (Axum)
            → CI (GitHub Actions)
                → Pre-commit (prek)
```

## Monorepo Structure

```
one-tap-trading/
  apps/
    web/              → Next.js 15, React 19, Tailwind v4
    indexer/           → Rust (Axum + Tokio)
  packages/
    contracts/         → Foundry (Solidity 0.8.28+)
    shared-types/      → TypeScript from ABIs (wagmi generate)
  docs/
    sdd/              → SDD artifacts
    PRD para Juego de Trading Web3.pdf
  turbo.json
  pnpm-workspace.yaml
  .github/workflows/ci.yml
  .prek.toml
```
