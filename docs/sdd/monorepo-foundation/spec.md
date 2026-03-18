# Spec: monorepo-foundation

> **Change**: monorepo-foundation
> **Status**: Draft
> **Date**: 2026-03-18
> **Version**: 1.0

## Executive Summary

This spec defines the complete monorepo foundation for One Tap Trading. It covers 8 areas with testable requirements and acceptance scenarios: monorepo structure, frontend scaffold, backend scaffold, contracts scaffold, shared types pipeline, CI/CD, pre-commit hooks, and dev experience.

All requirements are numbered and testable. Each area includes acceptance scenarios in Given/When/Then format.

---

## 1. Monorepo Structure

### Requirements

**1.1** Root directory must contain `pnpm-workspace.yaml` defining workspace members:
- `apps/web` (frontend)
- `apps/indexer` (backend)
- `packages/contracts` (smart contracts)
- `packages/shared-types` (generated types)

**1.2** `pnpm-workspace.yaml` must use catalog feature for shared dependencies:
- All workspaces reference shared versions via `catalog:` prefix
- Catalog includes: React 19, TypeScript 5.6+, Tailwind CSS 4, Vitest, oxlint

**1.3** Root `turbo.json` must define task pipeline with:
- Task definitions for `build`, `dev`, `test`, `lint`, `typecheck`
- Dependency graph: `contracts:build` → `shared-types:generate` → `web:build` / `indexer:build`
- Cache configuration with custom cache keys for Cargo.lock and foundry.lock
- Output globs for each task type

**1.4** Root `.env.example` must document all required environment variables:
- `NEXT_PUBLIC_*` variables for frontend
- `RUST_LOG` for backend
- `FOUNDRY_*` variables for contracts
- Each variable must have a comment explaining its purpose

**1.5** `.gitignore` must exclude:
- `node_modules/`, `dist/`, `build/`, `target/`
- `.env` (but NOT `.env.example`)
- Generated types in `packages/shared-types/generated/`
- Foundry artifacts in `packages/contracts/out/`

**1.6** Root `package.json` must define workspace scripts:
- `pnpm dev` — starts all workspaces concurrently
- `pnpm build` — builds all workspaces via Turborepo
- `pnpm test` — runs all tests (vitest + cargo test + forge test)
- `pnpm lint` — runs all linters (oxlint + cargo clippy + forge fmt)
- `pnpm typecheck` — runs tsc --noEmit for TypeScript workspaces

### Acceptance Scenarios

**Scenario 1.1: Developer clones repo and installs dependencies**
```
Given: Fresh clone of one-tap-trading
When: Developer runs `pnpm install`
Then: 
  - All workspaces resolve dependencies without conflicts
  - pnpm-workspace.yaml is valid YAML
  - No duplicate dependency versions across workspaces
  - Installation completes in < 2 minutes
```

**Scenario 1.2: Turborepo respects dependency chain**
```
Given: All workspaces are clean
When: Developer runs `pnpm build`
Then:
  - contracts:build runs first
  - shared-types:generate runs after contracts:build completes
  - web:build and indexer:build run in parallel after shared-types:generate
  - Total time is < 30s on cached run
```

**Scenario 1.3: Cache invalidation works for Rust**
```
Given: Successful build with cache
When: Developer modifies Cargo.lock in apps/indexer
Then:
  - Turborepo invalidates indexer:build cache
  - Next `pnpm build` rebuilds indexer (not from cache)
  - Other workspaces use cache
```

---

## 2. Frontend (apps/web)

### Requirements

**2.1** Next.js version must be 15.x (latest stable):
- `next@15.x` in package.json
- App Router enabled (no Pages Router)
- TypeScript strict mode enabled

**2.2** React version must be 19.x:
- `react@19.x` and `react-dom@19.x`
- No legacy Context API usage (use Zustand for state)

**2.3** Tailwind CSS version must be 4.x:
- `tailwindcss@4.x` with CSS-first configuration
- `@tailwindcss/typography` for markdown rendering (future use)
- Strict color palette defined in `tailwind.config.ts`

**2.4** TypeScript configuration (`tsconfig.json`) must enforce:
- `"strict": true`
- `"noUncheckedIndexedAccess": true`
- `"exactOptionalPropertyTypes": true`
- `"noImplicitOverride": true`
- `"noPropertyAccessFromIndexSignature": true`
- `"verbatimModuleSyntax": true`
- `"isolatedModules": true`
- `"moduleResolution": "bundler"`
- `"resolveJsonModule": true`
- `"allowSyntheticDefaultImports": true`

**2.5** Landing page must exist at `/` with:
- Hero section with app name and tagline
- Call-to-action button (placeholder, no functionality)
- Responsive design (mobile-first)
- Accessibility: WCAG 2.1 AA compliant (semantic HTML, alt text, color contrast)

**2.6** Linting must use oxlint:
- `oxlint` configured in `.oxlintrc.json` at workspace root
- Plugins enabled: `typescript`, `import`, `unicorn`
- No warnings allowed (fail on any warning)

**2.7** Testing must use Vitest:
- `vitest` configured in `vitest.config.ts`
- Test files colocated with source (`*.test.ts`, `*.test.tsx`)
- Minimum 80% coverage for non-UI code

**2.8** Build output must be optimized:
- `next build` produces `.next/` directory
- No console warnings or errors during build
- Bundle size < 500KB (gzipped)

### Acceptance Scenarios

**Scenario 2.1: Developer scaffolds frontend and runs dev server**
```
Given: apps/web/ directory exists with Next.js 15 scaffold
When: Developer runs `pnpm dev` from root
Then:
  - Next.js dev server starts on http://localhost:3000
  - Landing page loads without errors
  - Hot module replacement works (edit file, page updates)
  - No TypeScript errors in console
```

**Scenario 2.2: TypeScript strict mode catches errors**
```
Given: apps/web/src/page.tsx exists
When: Developer adds `const x: string = 123;` (type error)
Then:
  - `pnpm typecheck` fails with clear error message
  - Error points to exact line and column
  - Error message suggests fix
```

**Scenario 2.3: Linting prevents bad code**
```
Given: apps/web/ has oxlint configured
When: Developer adds unused variable or imports
Then:
  - `pnpm lint` fails
  - Error message identifies unused code
  - Developer can run `oxlint --fix` to auto-fix
```

**Scenario 2.4: Production build succeeds**
```
Given: All source files are valid
When: Developer runs `pnpm build` from root
Then:
  - Next.js build completes without errors
  - `.next/` directory is created
  - Bundle size is reported and < 500KB (gzipped)
  - No console warnings during build
```

---

## 3. Backend (apps/indexer)

### Requirements

**3.1** Rust edition must be 2021:
- `edition = "2021"` in Cargo.toml
- MSRV (minimum supported Rust version) = stable (auto-updated)

**3.2** Axum version must be 0.7.x:
- `axum = "0.7"` in Cargo.toml
- `tokio = { version = "1", features = ["full"] }`
- `serde = { version = "1", features = ["derive"] }`
- `serde_json = "1"`

**3.3** Health check endpoint must be implemented:
- **Path**: `GET /health`
- **Response format**: JSON
  ```json
  {
    "status": "ok",
    "timestamp": "2026-03-18T12:34:56Z",
    "version": "0.1.0"
  }
  ```
- **Status codes**:
  - `200 OK` when healthy
  - `503 Service Unavailable` when unhealthy (future use)
- **Response time**: < 10ms

**3.4** Server must start on configurable port:
- Default port: `3001` (via `RUST_LOG` or `PORT` env var)
- Bind to `0.0.0.0` (all interfaces)
- Graceful shutdown on SIGTERM

**3.5** Logging must use `tracing` crate:
- `tracing = "0.1"`
- `tracing-subscriber = "0.3"`
- Log level configurable via `RUST_LOG` env var
- Structured logging (JSON format in production)

**3.6** Cargo.toml must enforce lints:
```toml
[lints.clippy]
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "warn"
panic = "deny"
```

**3.7** Build profiles must be optimized:
- **dev**: `opt-level = 1` (fast compile, slow runtime)
- **release**: `opt-level = 3`, `lto = true` (slow compile, fast runtime)

**3.8** CORS middleware must be configured:
- Allow requests from `http://localhost:3000` (dev)
- Allow requests from `https://*.onetaptrading.com` (production, future)
- Allow credentials

### Acceptance Scenarios

**Scenario 3.1: Developer starts backend server**
```
Given: apps/indexer/ has Axum scaffold
When: Developer runs `pnpm dev` from root
Then:
  - Axum server starts on http://localhost:3001
  - Console shows "Server listening on 0.0.0.0:3001"
  - No compilation warnings
```

**Scenario 3.2: Health check endpoint responds**
```
Given: Backend server is running
When: Developer runs `curl http://localhost:3001/health`
Then:
  - Response status is 200 OK
  - Response body is valid JSON with status="ok"
  - Response time is < 10ms
```

**Scenario 3.3: Clippy lints prevent unsafe code**
```
Given: apps/indexer/ has clippy configured
When: Developer adds `let x = vec![1, 2, 3].unwrap();`
Then:
  - `cargo clippy` fails with "unwrap_used" error
  - Error message suggests using `?` operator or pattern matching
```

**Scenario 3.4: CORS allows frontend requests**
```
Given: Backend server is running with CORS middleware
When: Frontend (http://localhost:3000) makes request to /health
Then:
  - Request succeeds (no CORS error)
  - Response includes `Access-Control-Allow-Origin: http://localhost:3000`
```

---

## 4. Contracts (packages/contracts)

### Requirements

**4.1** Foundry must be configured:
- `foundry.toml` exists at workspace root
- Solidity compiler version: `0.8.28` or later
- Optimizer enabled: `optimizer = true`, `optimizer_runs = 200`

**4.2** Solidity version constraint:
- `pragma solidity ^0.8.28;` in all contracts
- No deprecated syntax (e.g., `selfdestruct` → `suicide`)

**4.3** Basic contract skeleton must exist:
- File: `packages/contracts/src/PerpEngine.sol`
- Implements minimal interface (no logic, just structure)
- Includes NatSpec comments for all public functions
- Compiles without warnings

**4.4** Test structure must mirror source:
- Test file: `packages/contracts/test/PerpEngine.t.sol`
- Uses Foundry's `Test` base class
- At least one passing test (e.g., `testHealthCheck()`)
- All tests pass: `forge test` returns exit code 0

**4.5** ABI output must be configured:
- `out/` directory contains compiled ABIs
- ABI format: JSON (standard Solidity ABI)
- ABIs are generated on `forge build`
- Path: `packages/contracts/out/PerpEngine.sol/PerpEngine.json`

**4.6** Remappings must be configured:
- `remappings = ["@openzeppelin/=lib/openzeppelin-contracts/"]` (if using OZ)
- Remappings allow clean imports: `import "@openzeppelin/token/ERC20/ERC20.sol";`

**4.7** Formatting must be enforced:
- `forge fmt` formats all `.sol` files
- No formatting warnings on `forge build`

### Acceptance Scenarios

**Scenario 4.1: Developer builds contracts**
```
Given: packages/contracts/ has Foundry scaffold
When: Developer runs `pnpm build` from root
Then:
  - `forge build` completes without errors
  - `packages/contracts/out/` directory is created
  - ABI JSON files are generated
  - No compiler warnings
```

**Scenario 4.2: Tests pass**
```
Given: packages/contracts/test/PerpEngine.t.sol exists
When: Developer runs `pnpm test` from root
Then:
  - `forge test` runs all tests
  - All tests pass (exit code 0)
  - Test output shows "X passed"
```

**Scenario 4.3: Formatting is enforced**
```
Given: packages/contracts/ has forge fmt configured
When: Developer adds poorly formatted code
Then:
  - `forge fmt --check` fails
  - Developer can run `forge fmt` to auto-fix
  - Next `forge fmt --check` passes
```

**Scenario 4.4: ABI is available for wagmi**
```
Given: Contracts are built
When: wagmi CLI runs
Then:
  - `packages/contracts/out/PerpEngine.sol/PerpEngine.json` exists
  - File contains valid ABI array
  - wagmi can parse and generate types from it
```

---

## 5. Shared Types (packages/shared-types)

### Requirements

**5.1** wagmi CLI must be configured:
- `wagmi.config.ts` exists at workspace root
- Configuration specifies input and output paths

**5.2** Input configuration:
- **Source**: `packages/contracts/out/` (Foundry ABI output)
- **Pattern**: `**/*.json` (all ABI files)
- **Validation**: ABIs must be valid Solidity ABI format

**5.3** Output configuration:
- **Target**: `packages/shared-types/generated/`
- **Format**: TypeScript files (`.ts`)
- **Exports**: Named exports for each contract type
- **Example**: `export type PerpEngineAbi = typeof PerpEngineAbi;`

**5.4** Build trigger must be automatic:
- `packages/shared-types/package.json` includes `"generate"` script
- Script runs `wagmi generate`
- Script is called by Turborepo before `web:build` and `indexer:build`
- Turborepo dependency: `shared-types:generate` depends on `contracts:build`

**5.5** Generated types must NOT be committed:
- `.gitignore` includes `packages/shared-types/generated/`
- CI generates types before building frontend/backend
- Local dev generates types on `pnpm install` or `pnpm build`

**5.6** TypeScript configuration for shared-types:
- `tsconfig.json` with strict mode enabled
- `"declaration": true` (generate `.d.ts` files)
- `"declarationMap": true` (source maps for types)

**5.7** Package exports must be clean:
- `package.json` includes `"exports"` field
- Exports point to generated types: `"./generated": "./generated/index.ts"`
- No direct imports from internal paths

### Acceptance Scenarios

**Scenario 5.1: Types are generated from ABIs**
```
Given: Contracts are built and ABIs exist
When: Developer runs `pnpm build` from root
Then:
  - `packages/shared-types/generated/` directory is created
  - TypeScript files are generated for each contract
  - Files include type definitions and React hooks
  - No TypeScript errors in generated files
```

**Scenario 5.2: Frontend can import generated types**
```
Given: Types are generated
When: Frontend imports `import { PerpEngineAbi } from "@shared-types/generated"`
Then:
  - Import resolves without error
  - Type definitions are available for autocomplete
  - No TypeScript errors
```

**Scenario 5.3: Generated types are not committed**
```
Given: Developer runs `pnpm build`
When: Developer runs `git status`
Then:
  - `packages/shared-types/generated/` is not listed as untracked
  - `.gitignore` includes the generated directory
  - CI will regenerate types before building
```

**Scenario 5.4: Dependency chain is enforced**
```
Given: All workspaces are clean
When: Developer runs `pnpm build`
Then:
  - contracts:build runs first
  - shared-types:generate runs after contracts:build
  - web:build and indexer:build run after shared-types:generate
  - Build fails if contracts:build fails (before shared-types:generate runs)
```

---

## 6. CI/CD (GitHub Actions)

### Requirements

**6.1** CI workflow file must exist:
- Path: `.github/workflows/ci.yml`
- Triggers: `on: [push, pull_request]`
- Runs on: `ubuntu-latest`

**6.2** Job matrix must cover all workspaces:
- **Lint job**: oxlint (frontend) + cargo clippy (backend) + forge fmt (contracts)
- **Typecheck job**: tsc --noEmit (frontend + shared-types)
- **Test job**: vitest (frontend) + cargo test (backend) + forge test (contracts)
- **Build job**: pnpm build (all workspaces)

**6.3** Toolchain setup must be automated:
- Node 22 LTS via `actions/setup-node@v4`
- Rust stable via `dtolnay/rust-toolchain@stable`
- Foundry via `foundry-rs/foundry-toolchain@v1`
- pnpm via `pnpm/action-setup@v2`

**6.4** Caching strategy:
- **pnpm store**: Cache `~/.pnpm-store` with key `pnpm-store-${{ hashFiles('**/pnpm-lock.yaml') }}`
- **Cargo registry**: Cache `~/.cargo/registry` with key `cargo-registry-${{ hashFiles('**/Cargo.lock') }}`
- **Cargo build**: Cache `target/` with key `cargo-build-${{ hashFiles('**/Cargo.lock') }}`
- **Foundry**: Cache `~/.foundry` with key `foundry-${{ runner.os }}`

**6.5** Required status checks:
- All jobs must pass before PR can be merged
- Status checks: `lint`, `typecheck`, `test`, `build`
- Timeout: 15 minutes per job

**6.6** Artifact retention:
- Build artifacts (`.next/`, `target/`, `out/`) are NOT uploaded
- Test reports are uploaded (if applicable)
- Retention: 7 days

**6.7** Failure notifications:
- Failed jobs must be visible in PR checks
- Error messages must be actionable (point to file:line)

### Acceptance Scenarios

**Scenario 6.1: CI runs on PR**
```
Given: Developer pushes branch to GitHub
When: PR is created
Then:
  - GitHub Actions workflow triggers automatically
  - All jobs (lint, typecheck, test, build) run in parallel
  - Results appear in PR checks section
  - Merge button is disabled until all checks pass
```

**Scenario 6.2: Lint job catches errors**
```
Given: Developer commits code with linting errors
When: CI runs
Then:
  - Lint job fails
  - Error message shows file:line of issue
  - PR shows "Lint job failed" in checks
  - Developer can see exact error in job logs
```

**Scenario 6.3: Caching speeds up CI**
```
Given: First CI run completes
When: Second CI run starts (same dependencies)
Then:
  - pnpm store is restored from cache
  - Cargo registry is restored from cache
  - Build time is 50% faster than first run
```

**Scenario 6.4: All jobs run in parallel**
```
Given: CI workflow is running
When: Observing job execution
Then:
  - Lint, typecheck, test, build jobs start simultaneously
  - Total CI time is ~5 minutes (not 20 minutes sequential)
  - Jobs don't block each other
```

---

## 7. Pre-commit Hooks (prek)

### Requirements

**7.1** prek configuration file must exist:
- Path: `.prek.toml` at root
- Format: TOML
- Defines all hooks to run before commit

**7.2** Hook list must include:
- **oxlint**: Lint TypeScript/JavaScript files
- **cargo clippy**: Lint Rust code
- **cargo fmt**: Format Rust code
- **forge fmt**: Format Solidity code

**7.3** oxlint hook configuration:
- **Command**: `oxlint --fix`
- **Files**: `**/*.{ts,tsx,js,jsx}`
- **Auto-fix**: Enabled (modifies files in-place)
- **Fail on error**: Yes (prevents commit if unfixable)

**7.4** cargo clippy hook configuration:
- **Command**: `cargo clippy --all-targets --all-features -- -D warnings`
- **Cwd**: `apps/indexer/`
- **Auto-fix**: No (clippy doesn't auto-fix)
- **Fail on error**: Yes

**7.5** cargo fmt hook configuration:
- **Command**: `cargo fmt --all`
- **Cwd**: `apps/indexer/`
- **Auto-fix**: Enabled (modifies files in-place)
- **Fail on error**: Yes

**7.6** forge fmt hook configuration:
- **Command**: `forge fmt`
- **Cwd**: `packages/contracts/`
- **Auto-fix**: Enabled (modifies files in-place)
- **Fail on error**: Yes

**7.7** Hook execution must be fast:
- Total hook time: < 30 seconds
- Hooks run in parallel where possible
- Hooks skip unchanged files

**7.8** Hook failures must be clear:
- Error messages point to file:line
- Developer can see exactly what failed
- Developer can run hook manually to debug

### Acceptance Scenarios

**Scenario 7.1: Developer commits code and hooks run**
```
Given: Developer has modified TypeScript files
When: Developer runs `git commit -m "message"`
Then:
  - prek hooks run automatically
  - oxlint runs and auto-fixes formatting issues
  - Commit proceeds if all hooks pass
  - Commit is blocked if hooks fail
```

**Scenario 7.2: Auto-fix modifies files**
```
Given: Developer commits poorly formatted code
When: prek hooks run
Then:
  - oxlint auto-fixes formatting
  - cargo fmt auto-fixes Rust formatting
  - forge fmt auto-fixes Solidity formatting
  - Developer sees "Files modified by hooks" message
  - Developer must re-stage files and commit again
```

**Scenario 7.3: Hook fails and prevents commit**
```
Given: Developer commits code with clippy error
When: prek hooks run
Then:
  - cargo clippy fails
  - Commit is blocked
  - Error message shows exact issue
  - Developer must fix code and try again
```

**Scenario 7.4: Hooks are fast**
```
Given: Developer commits changes
When: prek hooks run
Then:
  - Total hook time is < 30 seconds
  - Developer doesn't wait long for commit to complete
  - Hooks don't significantly slow down workflow
```

---

## 8. Dev Experience

### Requirements

**8.1** `pnpm dev` command must:
- Start all workspaces concurrently
- Frontend: Next.js dev server on http://localhost:3000
- Backend: Axum server on http://localhost:3001
- Contracts: Foundry watch mode (optional, for Phase 0)
- Output: Interleaved logs from all workspaces with color coding
- Exit: Graceful shutdown on Ctrl+C (all processes terminate)

**8.2** `pnpm build` command must:
- Build all workspaces via Turborepo
- Order: contracts → shared-types → web + indexer (parallel)
- Output: `.next/` (frontend), `target/release/` (backend), `out/` (contracts)
- Cache: Reuse cache from previous builds (< 30s on cached run)
- Exit code: 0 on success, non-zero on failure

**8.3** `pnpm test` command must:
- Run all tests: vitest (frontend) + cargo test (backend) + forge test (contracts)
- Output: Summary of passed/failed tests
- Coverage: Report coverage for frontend (target: 80%)
- Exit code: 0 if all tests pass, non-zero if any fail

**8.4** `pnpm lint` command must:
- Run all linters: oxlint (frontend) + cargo clippy (backend) + forge fmt (contracts)
- Output: List of issues with file:line references
- Auto-fix: Support `--fix` flag to auto-fix issues
- Exit code: 0 if no issues, non-zero if issues found

**8.5** `pnpm typecheck` command must:
- Run tsc --noEmit for TypeScript workspaces
- Output: List of type errors with file:line references
- Exit code: 0 if no errors, non-zero if errors found

**8.6** `pnpm install` command must:
- Install all dependencies for all workspaces
- Validate workspace protocol (no version conflicts)
- Generate shared types (wagmi generate)
- Exit code: 0 on success, non-zero on failure

**8.7** Environment setup must be validated:
- On `pnpm install` or `pnpm dev`, check `.env` file exists
- If missing, copy from `.env.example`
- Validate required variables are set
- Warn if optional variables are missing

**8.8** Documentation must be clear:
- `README.md` includes quick start guide
- Each workspace has its own `README.md` with setup instructions
- Commands are documented with examples

### Acceptance Scenarios

**Scenario 8.1: Developer runs pnpm dev and everything starts**
```
Given: Fresh clone with `pnpm install` completed
When: Developer runs `pnpm dev` from root
Then:
  - Frontend starts on http://localhost:3000
  - Backend starts on http://localhost:3001
  - Both servers are ready within 10 seconds
  - Logs show "Frontend ready" and "Backend listening"
  - Developer can access landing page in browser
  - Ctrl+C gracefully shuts down both servers
```

**Scenario 8.2: Developer builds for production**
```
Given: All source files are valid
When: Developer runs `pnpm build` from root
Then:
  - Build completes in < 30 seconds (cached)
  - `.next/` directory is created (frontend)
  - `target/release/` directory is created (backend)
  - `out/` directory is created (contracts)
  - No errors or warnings in output
  - Exit code is 0
```

**Scenario 8.3: Developer runs tests**
```
Given: All test files exist
When: Developer runs `pnpm test` from root
Then:
  - vitest runs frontend tests
  - cargo test runs backend tests
  - forge test runs contract tests
  - Output shows "X passed, Y failed"
  - Coverage report shows frontend coverage
  - Exit code is 0 if all pass, non-zero if any fail
```

**Scenario 8.4: Developer lints code**
```
Given: Code has linting issues
When: Developer runs `pnpm lint` from root
Then:
  - oxlint reports TypeScript issues
  - cargo clippy reports Rust issues
  - forge fmt reports Solidity formatting issues
  - Output shows file:line for each issue
  - Developer can run `pnpm lint --fix` to auto-fix
```

**Scenario 8.5: Developer typechecks code**
```
Given: Code has type errors
When: Developer runs `pnpm typecheck` from root
Then:
  - tsc reports type errors
  - Output shows file:line:column for each error
  - Error message suggests fix
  - Exit code is non-zero
```

**Scenario 8.6: Environment is validated on install**
```
Given: `.env` file is missing
When: Developer runs `pnpm install`
Then:
  - Script checks for `.env` file
  - If missing, copies from `.env.example`
  - Validates required variables are set
  - Warns if optional variables are missing
  - Installation completes successfully
```

---

## Testability Matrix

| Requirement | Test Method | Pass Criteria |
|-------------|------------|---------------|
| 1.1 - pnpm-workspace.yaml | Parse YAML, validate members | No errors, all members present |
| 1.2 - Catalog feature | Check package.json references | All deps use `catalog:` prefix |
| 1.3 - turbo.json pipeline | Run `pnpm build`, check order | Tasks run in correct order |
| 1.4 - .env.example | Check file exists, parse | All vars documented |
| 2.1 - Next.js 15 | Check package.json version | `next@15.x` present |
| 2.4 - TypeScript strict | Run `pnpm typecheck` | No errors, strict flags enabled |
| 3.2 - Axum 0.7 | Check Cargo.toml version | `axum = "0.7"` present |
| 3.3 - Health endpoint | `curl http://localhost:3001/health` | 200 OK, valid JSON |
| 4.1 - Foundry config | Check foundry.toml | Solc 0.8.28+, optimizer enabled |
| 4.4 - Tests pass | Run `forge test` | Exit code 0, all tests pass |
| 5.1 - wagmi.config.ts | Check file exists, parse | Valid TypeScript config |
| 5.5 - Generated types not committed | Check .gitignore | `packages/shared-types/generated/` excluded |
| 6.1 - CI workflow | Check `.github/workflows/ci.yml` | File exists, valid YAML |
| 6.5 - Required status checks | Create PR, check GitHub | All jobs required before merge |
| 7.1 - prek config | Check `.prek.toml` | File exists, valid TOML |
| 8.1 - pnpm dev | Run `pnpm dev`, check ports | Both servers start, ports open |

---

## Success Criteria (Testable)

- [ ] `pnpm install` completes without errors
- [ ] `pnpm dev` starts frontend (3000) + backend (3001) concurrently
- [ ] `pnpm build` completes in < 30s (cached) with exit code 0
- [ ] `pnpm test` runs all tests (vitest + cargo test + forge test) with exit code 0
- [ ] `pnpm lint` passes (oxlint + clippy + forge fmt) with exit code 0
- [ ] `pnpm typecheck` passes (tsc --noEmit) with exit code 0
- [ ] `GET /health` returns 200 OK with valid JSON
- [ ] `forge test` passes with exit code 0
- [ ] Generated types are not committed (in .gitignore)
- [ ] CI workflow runs on PR and all jobs pass
- [ ] Pre-commit hooks prevent broken commits
- [ ] Landing page loads at http://localhost:3000
- [ ] No TypeScript errors in any workspace
- [ ] No clippy warnings in backend
- [ ] No forge fmt issues in contracts

---

## Dependency Chain (Enforced by Turborepo)

```
contracts:build
    ↓
shared-types:generate
    ↓
web:build ← web:typecheck ← web:lint
indexer:build ← indexer:test ← indexer:lint
    ↓
CI (GitHub Actions)
```

---

## Out of Scope (Deferred)

- Database / persistence (in-memory only)
- Authentication / Account Abstraction
- Business logic (trading engine, pricing)
- Canvas rendering / real-time charts
- WebSocket infrastructure
- Oracle integration
- Deployment infrastructure
- Smart contract logic beyond skeleton

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-18 | Initial spec with 8 areas, 50+ requirements, 20+ scenarios |

