# Tasks: monorepo-foundation

> **Change**: monorepo-foundation
> **Status**: Ready for Implementation
> **Date**: 2026-03-18
> **Document Type**: Implementation Task Breakdown

## Executive Summary

This document breaks down the monorepo-foundation change into 32 granular, dependency-ordered tasks organized into 9 phases. Each task is completable in 1-3 tool calls and includes acceptance criteria.

**Total Effort**: ~3-4 days (single developer) or ~2 days (two developers in parallel)

**Key Phases**:
1. Root monorepo config (4 tasks)
2. Contracts scaffold (4 tasks)
3. Shared types pipeline (3 tasks)
4. Frontend scaffold (5 tasks)
5. Backend scaffold (5 tasks)
6. Turborepo wiring (3 tasks)
7. CI/CD setup (3 tasks)
8. Pre-commit hooks (2 tasks)
9. Validation & documentation (3 tasks)

---

## Phase 1: Root Monorepo Configuration

### Task 1.1: Create pnpm-workspace.yaml

**ID**: `1.1-pnpm-workspace`
**Description**: Initialize pnpm workspace with catalog for shared dependencies
**Dependencies**: None
**Files Affected**: `pnpm-workspace.yaml`
**Acceptance Criteria**:
- [ ] File exists at root
- [ ] Contains `packages:` section with `apps/*` and `packages/*`
- [ ] Contains `catalog:` section with React 19, TypeScript 5.7.2, Tailwind 4, Vitest, oxlint
- [ ] YAML is valid (no parse errors)
- [ ] `pnpm install` succeeds after creation

**Implementation Notes**:
- Use exact versions from design.md section 1
- Catalog enables workspace-wide version management

---

### Task 1.2: Create root package.json

**ID**: `1.2-root-package-json`
**Description**: Set up root package.json with workspace scripts and Turborepo
**Dependencies**: Task 1.1
**Files Affected**: `package.json`
**Acceptance Criteria**:
- [ ] File exists at root
- [ ] Contains scripts: `dev`, `build`, `test`, `lint`, `typecheck`, `format`
- [ ] All scripts use `turbo run` with appropriate flags
- [ ] `turbo@2.3.0` is in devDependencies
- [ ] `"type": "module"` is set
- [ ] Node >=22.0.0 and pnpm >=9.0.0 in engines

**Implementation Notes**:
- Use exact content from design.md section 1
- Scripts orchestrate all workspaces via Turborepo

---

### Task 1.3: Create turbo.json

**ID**: `1.3-turbo-json`
**Description**: Configure Turborepo task pipeline with dependency chain
**Dependencies**: Task 1.2
**Files Affected**: `turbo.json`
**Acceptance Criteria**:
- [ ] File exists at root
- [ ] Contains task definitions for: build, dev, test, lint, typecheck, format
- [ ] Contains specialized tasks: contracts#build, shared-types#generate, web#build, indexer#build
- [ ] Dependency chain enforced: contracts#build → shared-types#generate → web#build
- [ ] Cache configuration includes custom keys for Cargo.lock and foundry.lock
- [ ] JSON is valid (no parse errors)

**Implementation Notes**:
- Use exact content from design.md section 2
- This is the core orchestration file

---

### Task 1.4: Create .env.example and .gitignore

**ID**: `1.4-env-and-gitignore`
**Description**: Set up environment template and git exclusions
**Dependencies**: Task 1.3
**Files Affected**: `.env.example`, `.gitignore`
**Acceptance Criteria**:
- [ ] `.env.example` exists with all required variables documented
- [ ] Variables include: NEXT_PUBLIC_*, RUST_LOG, FOUNDRY_*
- [ ] Each variable has a comment explaining its purpose
- [ ] `.gitignore` excludes: node_modules/, dist/, build/, target/, .env, generated/
- [ ] `.gitignore` does NOT exclude `.env.example`
- [ ] `.gitignore` excludes `packages/contracts/out/`

**Implementation Notes**:
- Use exact content from design.md section 10
- .env.example is committed; .env is not

---

## Phase 2: Contracts Scaffold (Foundry)

### Task 2.1: Initialize Foundry project structure

**ID**: `2.1-foundry-init`
**Description**: Create Foundry project directories and foundry.toml
**Dependencies**: Task 1.4
**Files Affected**: `packages/contracts/foundry.toml`, `packages/contracts/src/`, `packages/contracts/test/`, `packages/contracts/script/`
**Acceptance Criteria**:
- [ ] Directory structure exists: src/, test/, script/, lib/
- [ ] `foundry.toml` exists with correct configuration
- [ ] Solidity compiler version set to 0.8.28
- [ ] Optimizer enabled with 200 runs
- [ ] EVM version set to cancun
- [ ] Formatting rules configured (line_length=100, tab_width=2)

**Implementation Notes**:
- Use exact content from design.md section 5
- Create directories if they don't exist

---

### Task 2.2: Create PerpEngine.sol contract

**ID**: `2.2-perp-engine-contract`
**Description**: Implement basic PerpEngine contract with interface and events
**Dependencies**: Task 2.1
**Files Affected**: `packages/contracts/src/PerpEngine.sol`
**Acceptance Criteria**:
- [ ] File exists with correct SPDX and pragma
- [ ] IPerpEngine interface defined with 3 functions: openPosition, closePosition, getPosition
- [ ] PerpEngine contract implements IPerpEngine
- [ ] Position struct defined with owner, asset, size, isLong, entryPrice, openedAt
- [ ] PositionOpened and PositionClosed events defined
- [ ] All public functions have NatSpec comments
- [ ] Contract compiles without warnings: `forge build`

**Implementation Notes**:
- Use exact content from design.md section 5
- This is a skeleton; business logic deferred to Phase 1+

---

### Task 2.3: Create PerpEngine.t.sol tests

**ID**: `2.3-perp-engine-tests`
**Description**: Write Foundry tests for PerpEngine contract
**Dependencies**: Task 2.2
**Files Affected**: `packages/contracts/test/PerpEngine.t.sol`
**Acceptance Criteria**:
- [ ] File exists with correct imports (forge-std/Test.sol, PerpEngine.sol)
- [ ] PerpEngineTest contract extends Test
- [ ] setUp() function initializes engine and test accounts
- [ ] At least 4 tests: test_OpenPosition, test_ClosePosition, test_RevertOnInvalidAsset, test_RevertOnZeroSize
- [ ] All tests pass: `forge test` returns exit code 0
- [ ] Test output shows "4 passed"

**Implementation Notes**:
- Use exact content from design.md section 5
- Tests verify basic contract behavior

---

### Task 2.4: Create contracts package.json

**ID**: `2.4-contracts-package-json`
**Description**: Set up package.json for contracts workspace
**Dependencies**: Task 2.3
**Files Affected**: `packages/contracts/package.json`
**Acceptance Criteria**:
- [ ] File exists with name `@one-tap-trading/contracts`
- [ ] Contains scripts: build (forge build), test (forge test), fmt (forge fmt)
- [ ] No npm dependencies (Foundry is standalone)
- [ ] Private: true

**Implementation Notes**:
- Minimal package.json; Foundry is the primary tool

---

## Phase 3: Shared Types Pipeline (wagmi)

### Task 3.1: Create shared-types package.json

**ID**: `3.1-shared-types-package-json`
**Description**: Set up shared-types workspace with wagmi CLI
**Dependencies**: Task 2.4
**Files Affected**: `packages/shared-types/package.json`
**Acceptance Criteria**:
- [ ] File exists with name `@one-tap-trading/shared-types`
- [ ] Contains script: `generate` (wagmi generate)
- [ ] Dependencies: wagmi ^2.12.0, viem ^2.21.0
- [ ] DevDependencies: @wagmi/cli ^2.1.0, typescript, @types/node
- [ ] Exports field points to generated types
- [ ] Private: true

**Implementation Notes**:
- Use exact content from design.md section 6
- wagmi CLI generates types from contract ABIs

---

### Task 3.2: Create wagmi.config.ts

**ID**: `3.2-wagmi-config`
**Description**: Configure wagmi CLI to read Foundry ABIs and generate types
**Dependencies**: Task 3.1
**Files Affected**: `packages/shared-types/wagmi.config.ts`
**Acceptance Criteria**:
- [ ] File exists with valid TypeScript
- [ ] defineConfig() called with foundry plugin
- [ ] Input path: `../contracts` (Foundry project)
- [ ] Output path: `src/generated/index.ts`
- [ ] Include pattern: `PerpEngine.sol/**`
- [ ] File is valid TypeScript (no syntax errors)

**Implementation Notes**:
- Use exact content from design.md section 6
- This bridges Foundry ABIs to TypeScript types

---

### Task 3.3: Create shared-types tsconfig.json and index.ts

**ID**: `3.3-shared-types-config`
**Description**: Set up TypeScript config and re-export generated types
**Dependencies**: Task 3.2
**Files Affected**: `packages/shared-types/tsconfig.json`, `packages/shared-types/src/index.ts`
**Acceptance Criteria**:
- [ ] `tsconfig.json` exists with strict mode enabled
- [ ] `declaration: true` and `declarationMap: true` set
- [ ] `src/index.ts` exists and re-exports from generated/
- [ ] Helper function `isPerpEngineABI()` defined
- [ ] TypeScript compiles without errors: `tsc --noEmit`

**Implementation Notes**:
- Use exact content from design.md section 6
- Re-export pattern allows clean imports in frontend/backend

---

## Phase 4: Frontend Scaffold (Next.js 15)

### Task 4.1: Create apps/web package.json

**ID**: `4.1-web-package-json`
**Description**: Set up Next.js 15 workspace with dependencies
**Dependencies**: Task 1.1 (catalog)
**Files Affected**: `apps/web/package.json`
**Acceptance Criteria**:
- [ ] File exists with name `@one-tap-trading/web`
- [ ] Next.js 15.1.0 in dependencies
- [ ] React 19.0.0 and react-dom 19.0.0 in dependencies
- [ ] Workspace dependency: `@one-tap-trading/shared-types: workspace:*`
- [ ] Scripts: dev, build, start, lint, typecheck, test, format
- [ ] DevDependencies: typescript, tailwindcss, oxlint, vitest, jsdom
- [ ] Private: true

**Implementation Notes**:
- Use exact content from design.md section 3
- Workspace protocol ensures local shared-types resolution

---

### Task 4.2: Create apps/web/tsconfig.json

**ID**: `4.2-web-tsconfig`
**Description**: Configure strict TypeScript for Next.js
**Dependencies**: Task 4.1
**Files Affected**: `apps/web/tsconfig.json`
**Acceptance Criteria**:
- [ ] File exists with all strict flags enabled
- [ ] `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`
- [ ] `noImplicitOverride: true`, `noPropertyAccessFromIndexSignature: true`
- [ ] `verbatimModuleSyntax: true`, `isolatedModules: true`
- [ ] `moduleResolution: "bundler"`, `resolveJsonModule: true`
- [ ] Path alias: `@/*` → `./src/*`
- [ ] TypeScript compiles without errors: `tsc --noEmit`

**Implementation Notes**:
- Use exact content from design.md section 3
- Strict mode catches type errors early

---

### Task 4.3: Create Next.js config and Tailwind config

**ID**: `4.3-web-configs`
**Description**: Set up next.config.ts and tailwind.config.ts
**Dependencies**: Task 4.2
**Files Affected**: `apps/web/next.config.ts`, `apps/web/tailwind.config.ts`
**Acceptance Criteria**:
- [ ] `next.config.ts` exists with reactStrictMode: true
- [ ] `swcMinify: true` for faster builds
- [ ] `experimental.optimizePackageImports` includes shared-types
- [ ] `tailwind.config.ts` exists with content paths configured
- [ ] Theme colors defined: primary, secondary, accent
- [ ] Both files are valid TypeScript

**Implementation Notes**:
- Use exact content from design.md section 3
- Tailwind v4 uses CSS-first configuration

---

### Task 4.4: Create app layout and landing page

**ID**: `4.4-web-landing-page`
**Description**: Implement Next.js App Router layout and landing page
**Dependencies**: Task 4.3
**Files Affected**: `apps/web/src/app/layout.tsx`, `apps/web/src/app/page.tsx`, `apps/web/src/app/globals.css`
**Acceptance Criteria**:
- [ ] `layout.tsx` exists with RootLayout component
- [ ] Metadata set: title="One Tap Trading", description="Gamified trading on MegaETH"
- [ ] Layout includes header with nav and main content area
- [ ] `page.tsx` exists with landing page content
- [ ] Page imports PerpEngineABI from shared-types
- [ ] Page displays hero section, tagline, and system status
- [ ] `globals.css` exists with Tailwind directives
- [ ] Page loads without errors: `next dev` starts successfully

**Implementation Notes**:
- Use exact content from design.md section 3
- Landing page is placeholder; full UI deferred to Phase 1+

---

### Task 4.5: Create vitest config for frontend

**ID**: `4.5-web-vitest-config`
**Description**: Set up Vitest for frontend testing
**Dependencies**: Task 4.4
**Files Affected**: `apps/web/vitest.config.ts`
**Acceptance Criteria**:
- [ ] File exists with valid TypeScript
- [ ] defineConfig() called with jsdom environment
- [ ] Test files pattern: `**/*.test.ts`, `**/*.test.tsx`
- [ ] Coverage configuration included
- [ ] Vitest runs without errors: `vitest --run`

**Implementation Notes**:
- Minimal config; tests added in Phase 1+

---

## Phase 5: Backend Scaffold (Rust Axum)

### Task 5.1: Create apps/indexer Cargo.toml

**ID**: `5.1-indexer-cargo-toml`
**Description**: Set up Rust workspace with Axum and dependencies
**Dependencies**: Task 1.1
**Files Affected**: `apps/indexer/Cargo.toml`
**Acceptance Criteria**:
- [ ] File exists with package name "indexer"
- [ ] Edition 2021
- [ ] Dependencies: axum 0.7, tokio 1 (full features), tower, tower-http, tracing, serde, serde_json
- [ ] Clippy lints configured: pedantic, unwrap_used=deny, panic=deny, etc.
- [ ] Build profiles: dev (opt-level=0), release (opt-level=3, lto=true)
- [ ] `cargo check` succeeds

**Implementation Notes**:
- Use exact content from design.md section 4
- Clippy lints enforce code quality

---

### Task 5.2: Create apps/indexer/src/main.rs

**ID**: `5.2-indexer-main`
**Description**: Implement Axum server with health endpoint
**Dependencies**: Task 5.1
**Files Affected**: `apps/indexer/src/main.rs`
**Acceptance Criteria**:
- [ ] File exists with valid Rust
- [ ] #[tokio::main] async main function
- [ ] Router created with GET /health route
- [ ] CorsLayer configured (permissive for Phase 0)
- [ ] Server binds to 127.0.0.1:3001
- [ ] Tracing initialized with RUST_LOG env var
- [ ] Graceful shutdown on SIGTERM
- [ ] `cargo build` succeeds without warnings

**Implementation Notes**:
- Use exact content from design.md section 4
- Health endpoint is the only route in Phase 0

---

### Task 5.3: Create apps/indexer/src/handlers/health.rs

**ID**: `5.3-indexer-health-handler`
**Description**: Implement health check endpoint handler
**Dependencies**: Task 5.2
**Files Affected**: `apps/indexer/src/handlers/health.rs`, `apps/indexer/src/handlers/mod.rs`
**Acceptance Criteria**:
- [ ] `handlers/health.rs` exists with async handler function
- [ ] Returns (StatusCode::OK, JSON response)
- [ ] JSON includes: status="ok", service="indexer", version="0.0.1"
- [ ] Unit test: test_health_endpoint() verifies response
- [ ] `handlers/mod.rs` exists and exports health module
- [ ] `cargo test` passes all tests

**Implementation Notes**:
- Use exact content from design.md section 4
- Handler is tested with #[tokio::test]

---

### Task 5.4: Create apps/indexer/.cargo/config.toml

**ID**: `5.4-indexer-cargo-config`
**Description**: Configure Cargo build settings for indexer
**Dependencies**: Task 5.3
**Files Affected**: `apps/indexer/.cargo/config.toml`
**Acceptance Criteria**:
- [ ] File exists with valid TOML
- [ ] Incremental compilation enabled for dev
- [ ] Parallel compilation configured
- [ ] Optional: custom linker or other optimizations

**Implementation Notes**:
- Minimal config; can be empty or contain build optimizations

---

### Task 5.5: Create apps/indexer/src/middleware/mod.rs

**ID**: `5.5-indexer-middleware`
**Description**: Set up middleware module structure
**Dependencies**: Task 5.4
**Files Affected**: `apps/indexer/src/middleware/mod.rs`
**Acceptance Criteria**:
- [ ] File exists (can be empty or contain future middleware)
- [ ] Module is declared in main.rs
- [ ] Compiles without errors

**Implementation Notes**:
- Placeholder for future middleware (logging, auth, etc.)

---

## Phase 6: Turborepo Wiring

### Task 6.1: Wire contracts#build → shared-types#generate dependency

**ID**: `6.1-turbo-contracts-to-types`
**Description**: Ensure Turborepo enforces contracts build before type generation
**Dependencies**: Task 1.3 (turbo.json), Task 2.4 (contracts), Task 3.1 (shared-types)
**Files Affected**: `turbo.json` (already created, verify)
**Acceptance Criteria**:
- [ ] turbo.json contains `shared-types#generate` task
- [ ] Task has `dependsOn: ["contracts#build"]`
- [ ] Task inputs include `packages/contracts/out/**/*.json`
- [ ] Task outputs include `packages/shared-types/src/generated/**`
- [ ] Run `pnpm build` and verify order: contracts builds first, then types generate

**Implementation Notes**:
- Verify turbo.json from Task 1.3 has this dependency

---

### Task 6.2: Wire shared-types#generate → web#build dependency

**ID**: `6.2-turbo-types-to-web`
**Description**: Ensure Turborepo enforces type generation before web build
**Dependencies**: Task 6.1, Task 4.1 (web)
**Files Affected**: `turbo.json` (verify)
**Acceptance Criteria**:
- [ ] turbo.json contains `web#build` task
- [ ] Task has `dependsOn: ["^build", "shared-types#generate"]`
- [ ] Task outputs include `.next/**`
- [ ] Run `pnpm build` and verify: types generate before web builds
- [ ] Web can import from @one-tap-trading/shared-types without errors

**Implementation Notes**:
- Verify turbo.json from Task 1.3 has this dependency

---

### Task 6.3: Verify full build pipeline

**ID**: `6.3-turbo-full-pipeline`
**Description**: Test complete Turborepo pipeline with all workspaces
**Dependencies**: Task 6.2, all Phase 4 & 5 tasks
**Files Affected**: None (verification only)
**Acceptance Criteria**:
- [ ] Run `pnpm install` from root — succeeds
- [ ] Run `pnpm build` from root — completes in order: contracts → types → web + indexer
- [ ] Build time < 30s on cached run
- [ ] All outputs exist: .next/, target/release/, packages/contracts/out/
- [ ] No TypeScript errors in web
- [ ] No Rust compilation warnings in indexer
- [ ] No Solidity compiler warnings in contracts

**Implementation Notes**:
- This is a verification task; no new files created

---

## Phase 7: CI/CD Setup

### Task 7.1: Create .github/workflows/ci.yml

**ID**: `7.1-github-actions-ci`
**Description**: Set up GitHub Actions workflow for lint, typecheck, test, build
**Dependencies**: Task 6.3 (full pipeline working)
**Files Affected**: `.github/workflows/ci.yml`
**Acceptance Criteria**:
- [ ] File exists with valid YAML
- [ ] Triggers on: push to main, pull_request to main
- [ ] Jobs: lint, typecheck, test, build
- [ ] Lint job runs oxlint, cargo clippy, forge fmt
- [ ] Typecheck job runs tsc --noEmit
- [ ] Test job runs vitest, cargo test, forge test
- [ ] Build job depends on lint, typecheck, test
- [ ] All jobs run on ubuntu-latest
- [ ] Node 22, Rust stable, Foundry toolchain installed
- [ ] pnpm caching configured

**Implementation Notes**:
- Use exact content from design.md section 7
- Actions pinned to SHA hashes with version comments

---

### Task 7.2: Configure GitHub branch protection

**ID**: `7.2-github-branch-protection`
**Description**: Require CI checks before merge to main
**Dependencies**: Task 7.1
**Files Affected**: None (GitHub settings)
**Acceptance Criteria**:
- [ ] Branch protection rule created for main
- [ ] Required status checks: lint, typecheck, test, build
- [ ] Require branches to be up to date before merge
- [ ] Require code review (optional for Phase 0)
- [ ] Dismiss stale PR approvals on new commits

**Implementation Notes**:
- Configure via GitHub UI or GitHub CLI

---

### Task 7.3: Verify CI runs on PR

**ID**: `7.3-ci-verification`
**Description**: Create test PR and verify all CI jobs pass
**Dependencies**: Task 7.2
**Files Affected**: None (verification only)
**Acceptance Criteria**:
- [ ] Create feature branch with small change (e.g., update README)
- [ ] Push to GitHub and create PR
- [ ] GitHub Actions workflow triggers automatically
- [ ] All jobs (lint, typecheck, test, build) run in parallel
- [ ] All jobs pass (green checkmarks)
- [ ] PR shows "All checks passed"
- [ ] Merge button is enabled

**Implementation Notes**:
- This is a verification task; no new files created

---

## Phase 8: Pre-commit Hooks

### Task 8.1: Create .prek.toml

**ID**: `8.1-prek-config`
**Description**: Configure pre-commit hooks with prek
**Dependencies**: Task 1.4 (.gitignore)
**Files Affected**: `.prek.toml`
**Acceptance Criteria**:
- [ ] File exists with valid TOML
- [ ] Hooks defined: oxlint, oxfmt, cargo-fmt, cargo-clippy, forge-fmt
- [ ] oxlint hook: runs on *.ts, *.tsx, *.js, *.jsx files
- [ ] oxfmt hook: auto-fixes formatting
- [ ] cargo-fmt hook: formats Rust code
- [ ] cargo-clippy hook: lints Rust code, fails on warnings
- [ ] forge-fmt hook: formats Solidity code
- [ ] All hooks have descriptions and stages

**Implementation Notes**:
- Use exact content from design.md section 8
- prek is a Rust-based pre-commit tool (faster than Python)

---

### Task 8.2: Install and test prek hooks

**ID**: `8.2-prek-install`
**Description**: Install prek and verify hooks work
**Dependencies**: Task 8.1
**Files Affected**: `.git/hooks/` (auto-generated)
**Acceptance Criteria**:
- [ ] Run `prek install` from root
- [ ] Hooks are installed in .git/hooks/
- [ ] Make a small code change (e.g., add unused variable)
- [ ] Run `git commit -m "test"` — hooks run and catch the issue
- [ ] Hooks prevent commit if issues found
- [ ] Fix the issue and commit succeeds
- [ ] Total hook time < 30 seconds

**Implementation Notes**:
- prek must be installed globally or via Homebrew
- Hooks run automatically on `git commit`

---

## Phase 9: Validation & Documentation

### Task 9.1: Create root README.md

**ID**: `9.1-root-readme`
**Description**: Write quick start guide and project overview
**Dependencies**: All previous tasks
**Files Affected**: `README.md`
**Acceptance Criteria**:
- [ ] File exists at root
- [ ] Includes project description: "Gamified trading web app on MegaETH"
- [ ] Quick start section: clone, install, dev, build, test, lint
- [ ] Workspace structure documented
- [ ] Commands documented with examples
- [ ] Links to SDD artifacts (proposal, spec, design)
- [ ] Prerequisites: Node 22, pnpm 9, Rust, Foundry

**Implementation Notes**:
- Clear, concise documentation for new developers

---

### Task 9.2: Create workspace READMEs

**ID**: `9.2-workspace-readmes`
**Description**: Write README for each workspace (web, indexer, contracts, shared-types)
**Dependencies**: Task 9.1
**Files Affected**: `apps/web/README.md`, `apps/indexer/README.md`, `packages/contracts/README.md`, `packages/shared-types/README.md`
**Acceptance Criteria**:
- [ ] Each workspace has a README
- [ ] Web README: Next.js 15, React 19, Tailwind v4, dev/build/test commands
- [ ] Indexer README: Rust Axum, health endpoint, dev/build/test commands
- [ ] Contracts README: Foundry, PerpEngine contract, forge build/test commands
- [ ] Shared-types README: wagmi CLI, type generation, usage in other workspaces
- [ ] Each README includes setup instructions specific to that workspace

**Implementation Notes**:
- Workspace-specific documentation helps developers navigate

---

### Task 9.3: Full validation and sign-off

**ID**: `9.3-full-validation`
**Description**: Run all commands and verify everything works end-to-end
**Dependencies**: All previous tasks
**Files Affected**: None (verification only)
**Acceptance Criteria**:
- [ ] `pnpm install` completes without errors
- [ ] `pnpm dev` starts frontend (3000) + backend (3001) concurrently
- [ ] Frontend landing page loads at http://localhost:3000
- [ ] Backend health endpoint responds at http://localhost:3001/health
- [ ] `pnpm build` completes in < 30s (cached) with exit code 0
- [ ] `pnpm test` runs all tests (vitest + cargo test + forge test) with exit code 0
- [ ] `pnpm lint` passes (oxlint + clippy + forge fmt) with exit code 0
- [ ] `pnpm typecheck` passes (tsc --noEmit) with exit code 0
- [ ] No TypeScript errors in any workspace
- [ ] No Rust compilation warnings
- [ ] No Solidity compiler warnings
- [ ] Pre-commit hooks prevent broken commits
- [ ] CI workflow passes on PR
- [ ] Generated types are not in git history
- [ ] All workspaces can import from shared-types

**Implementation Notes**:
- This is the final verification task
- If all criteria pass, monorepo-foundation is complete

---

## Task Dependency Graph

```
Phase 1: Root Config
├── 1.1: pnpm-workspace.yaml
├── 1.2: root package.json (depends on 1.1)
├── 1.3: turbo.json (depends on 1.2)
└── 1.4: .env.example + .gitignore (depends on 1.3)

Phase 2: Contracts
├── 2.1: Foundry init (depends on 1.4)
├── 2.2: PerpEngine.sol (depends on 2.1)
├── 2.3: PerpEngine.t.sol (depends on 2.2)
└── 2.4: contracts package.json (depends on 2.3)

Phase 3: Shared Types
├── 3.1: shared-types package.json (depends on 2.4)
├── 3.2: wagmi.config.ts (depends on 3.1)
└── 3.3: tsconfig + index.ts (depends on 3.2)

Phase 4: Frontend
├── 4.1: web package.json (depends on 1.1)
├── 4.2: web tsconfig.json (depends on 4.1)
├── 4.3: next.config + tailwind.config (depends on 4.2)
├── 4.4: layout + page (depends on 4.3)
└── 4.5: vitest config (depends on 4.4)

Phase 5: Backend
├── 5.1: indexer Cargo.toml (depends on 1.1)
├── 5.2: main.rs (depends on 5.1)
├── 5.3: health handler (depends on 5.2)
├── 5.4: .cargo/config.toml (depends on 5.3)
└── 5.5: middleware/mod.rs (depends on 5.4)

Phase 6: Turborepo Wiring
├── 6.1: contracts → types (depends on 1.3, 2.4, 3.1)
├── 6.2: types → web (depends on 6.1, 4.1)
└── 6.3: full pipeline (depends on 6.2, all Phase 4 & 5)

Phase 7: CI/CD
├── 7.1: ci.yml (depends on 6.3)
├── 7.2: branch protection (depends on 7.1)
└── 7.3: CI verification (depends on 7.2)

Phase 8: Pre-commit
├── 8.1: .prek.toml (depends on 1.4)
└── 8.2: prek install (depends on 8.1)

Phase 9: Validation
├── 9.1: root README (depends on all)
├── 9.2: workspace READMEs (depends on 9.1)
└── 9.3: full validation (depends on all)
```

---

## Parallel Execution Strategy

**Two-Developer Approach** (2 days):

**Developer A (Frontend + Shared Types)**:
- Phase 1: Root config (1 day)
- Phase 3: Shared types (2 hours)
- Phase 4: Frontend (4 hours)
- Phase 9.1: Root README (1 hour)

**Developer B (Backend + Contracts)**:
- Phase 2: Contracts (3 hours)
- Phase 5: Backend (4 hours)
- Phase 8: Pre-commit hooks (1 hour)
- Phase 9.2: Workspace READMEs (1 hour)

**Together**:
- Phase 6: Turborepo wiring (1 hour)
- Phase 7: CI/CD (2 hours)
- Phase 9.3: Full validation (1 hour)

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| All tasks completed | 32/32 | Checklist 100% |
| Build time (cached) | < 30s | `time pnpm build` |
| CI passes | 100% | GitHub Actions green |
| Test coverage | 80%+ (frontend) | `pnpm test` output |
| No warnings | 0 | `pnpm lint` exit code 0 |
| Type safety | 100% | `pnpm typecheck` exit code 0 |
| Pre-commit hooks | < 30s | `git commit` timing |
| Documentation | Complete | All READMEs written |

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-18 | Initial task breakdown with 32 tasks across 9 phases |

