# Spec-Driven Development (SDD) Artifacts

This directory contains all SDD artifacts for the One Tap Trading project.

Each change gets its own subdirectory with the following artifacts:

| Artifact | Description |
|----------|-------------|
| `explore.md` | Investigation and findings before committing to the change |
| `proposal.md` | Intent, scope, approach, success criteria |
| `spec.md` | Requirements and scenarios |
| `design.md` | Technical design and architecture decisions |
| `tasks.md` | Implementation task checklist |

## Active Changes

- [`monorepo-foundation/`](./monorepo-foundation/) — Monorepo setup with Turborepo, Next.js, Rust Axum, Foundry, shared types, CI

## SDD Config

- **Artifact store**: engram + openspec (dual mode)
- **Naming**: `sdd/{change-name}/{artifact-type}`
- **Project**: one-tap-trading
