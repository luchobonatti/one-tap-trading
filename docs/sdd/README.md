# Spec-Driven Development (SDD) Artifacts

This directory contains file-based SDD artifacts. The primary artifact store is **engram** (persistent memory); see engram observations prefixed `sdd/` for the canonical versions.

Each change gets its own subdirectory with the following artifacts:

| Artifact | Description |
|----------|-------------|
| `explore.md` | Investigation and findings before committing to the change |
| `proposal.md` | Intent, scope, approach, success criteria |
| `spec.md` | Requirements and scenarios |
| `design.md` | Technical design and architecture decisions |
| `tasks.md` | Implementation task checklist |

## Active Changes

- [`monorepo-foundation/`](./monorepo-foundation/) — Monorepo setup: Turborepo, Next.js, Rust Axum, Foundry, shared types, CI ✅ complete
- `phase3-game-interface/` — Space-themed PixiJS game canvas (engram only) 🔄 in progress

## Completed Changes (engram)

- `phase2-aa` — Account abstraction: passkeys, session keys, VerifyingPaymaster ✅
- `phase2d-contracts` — SKV + paymaster redeploy with installValidations whitelist ✅

## SDD Config

- **Artifact store**: engram (primary) — search `sdd/{change-name}/{artifact-type}`
- **Naming**: `sdd/{change-name}/{artifact-type}`
- **Project**: one-tap-trading
