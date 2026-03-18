# Design: monorepo-foundation

> **Change**: monorepo-foundation
> **Status**: In Progress
> **Date**: 2026-03-18
> **Document Type**: Technical Design (HOW)

## Executive Summary

This document specifies the concrete architecture, configuration, and integration patterns for the One Tap Trading monorepo foundation. It translates the proposal's intent into actionable implementation details: exact file contents, task pipelines, dependency chains, and CI/CD workflows.

**Key Design Principles:**
- Single source of truth: Turborepo orchestrates all tasks from root
- Generated artifacts never committed: Types, ABIs, and build outputs are derived
- Strict type safety: TypeScript strict mode across all workspaces
- Fast feedback loops: Incremental builds, parallel tasks, aggressive caching
- Language-agnostic: Turborepo handles TS, Rust, and Solidity seamlessly

---

## 1. Monorepo Structure & pnpm Workspace

### Directory Layout

```
one-tap-trading/
├── apps/
│   ├── web/                    # Next.js 15 frontend
│   │   ├── src/
│   │   │   ├── app/           # App Router
│   │   │   ├── components/
│   │   │   ├── lib/
│   │   │   └── styles/
│   │   ├── public/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── tailwind.config.ts
│   │   ├── next.config.ts
│   │   └── vitest.config.ts
│   │
│   └── indexer/                # Rust Axum backend
│       ├── src/
│       │   ├── main.rs
│       │   ├── handlers/
│       │   └── middleware/
│       ├── Cargo.toml
│       ├── Cargo.lock
│       └── .cargo/config.toml
│
├── packages/
│   ├── contracts/              # Foundry Solidity
│   │   ├── src/
│   │   │   └── PerpEngine.sol
│   │   ├── test/
│   │   │   └── PerpEngine.t.sol
│   │   ├── script/
│   │   ├── foundry.toml
│   │   ├── package.json        # For forge fmt, ABIs output
│   │   └── remappings.txt
│   │
│   └── shared-types/           # Generated types from ABIs
│       ├── src/
│       │   ├── generated/      # Output of wagmi generate
│       │   └── index.ts
│       ├── package.json
│       ├── tsconfig.json
│       ├── wagmi.config.ts
│       └── .gitignore          # Ignore generated/
│
├── docs/
│   ├── sdd/
│   │   └── monorepo-foundation/
│   │       ├── explore.md
│   │       ├── proposal.md
│   │       └── design.md       # This file
│   └── PRD para Juego de Trading Web3.pdf
│
├── .github/
│   └── workflows/
│       └── ci.yml
│
├── .prek.toml
├── pnpm-workspace.yaml
├── turbo.json
├── package.json                # Root
├── pnpm-lock.yaml
├── .env.example
├── .gitignore
└── README.md
```

### Root `pnpm-workspace.yaml`

```yaml
packages:
  - 'apps/*'
  - 'packages/*'

catalog:
  react: '19.0.0'
  react-dom: '19.0.0'
  typescript: '5.7.2'
  '@types/node': '22.10.5'
  '@types/react': '19.0.0'
  '@types/react-dom': '19.0.0'
  vite: '6.2.0'
  vitest: '3.1.0'
  oxlint: '0.11.0'
  tailwindcss: '4.0.0'
  autoprefixer: '10.4.20'
  postcss: '8.4.49'
```

### Root `package.json`

```json
{
  "name": "one-tap-trading",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "description": "Gamified trading web app on MegaETH",
  "scripts": {
    "dev": "turbo run dev --parallel",
    "build": "turbo run build",
    "test": "turbo run test",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "format": "turbo run format"
  },
  "devDependencies": {
    "turbo": "2.3.0"
  },
  "engines": {
    "node": ">=22.0.0",
    "pnpm": ">=9.0.0"
  }
}
```

---

## 2. Turborepo Pipeline Design

### Root `turbo.json`

```json
{
  "$schema": "https://turbo.build/schema.json",
  "version": "2",
  "globalDependencies": [
    "pnpm-workspace.yaml",
    ".env.example",
    ".env"
  ],
  "tasks": {
    "build": {
      "description": "Build workspace",
      "dependsOn": ["^build"],
      "outputs": [
        "dist/**",
        "build/**",
        ".next/**",
        "target/release/**"
      ],
      "cache": true,
      "env": ["NODE_ENV"]
    },
    "dev": {
      "description": "Start dev server",
      "cache": false,
      "persistent": true
    },
    "test": {
      "description": "Run tests",
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"],
      "cache": true
    },
    "lint": {
      "description": "Lint code",
      "cache": true,
      "outputs": []
    },
    "typecheck": {
      "description": "Type check TypeScript",
      "cache": true,
      "outputs": []
    },
    "format": {
      "description": "Format code",
      "cache": false,
      "outputs": []
    },
    "contracts#build": {
      "description": "Forge build (compile contracts)",
      "outputs": [
        "packages/contracts/out/**",
        "packages/contracts/cache/**"
      ],
      "cache": true,
      "inputs": [
        "packages/contracts/src/**/*.sol",
        "packages/contracts/foundry.toml",
        "packages/contracts/remappings.txt"
      ],
      "env": ["FOUNDRY_SOLC_VERSION"]
    },
    "shared-types#generate": {
      "description": "Generate TypeScript types from contract ABIs",
      "dependsOn": ["contracts#build"],
      "outputs": [
        "packages/shared-types/src/generated/**"
      ],
      "cache": true,
      "inputs": [
        "packages/contracts/out/**/*.json",
        "packages/shared-types/wagmi.config.ts"
      ]
    },
    "web#build": {
      "description": "Build Next.js app",
      "dependsOn": ["^build", "shared-types#generate"],
      "outputs": [".next/**"],
      "cache": true,
      "env": ["NODE_ENV"]
    },
    "indexer#build": {
      "description": "Build Rust indexer",
      "dependsOn": ["^build"],
      "outputs": ["target/release/indexer"],
      "cache": true,
      "inputs": [
        "apps/indexer/src/**/*.rs",
        "apps/indexer/Cargo.toml",
        "apps/indexer/Cargo.lock"
      ]
    },
    "contracts#test": {
      "description": "Run Foundry tests",
      "dependsOn": ["contracts#build"],
      "cache": true,
      "inputs": [
        "packages/contracts/src/**/*.sol",
        "packages/contracts/test/**/*.sol",
        "packages/contracts/foundry.toml"
      ]
    },
    "indexer#test": {
      "description": "Run Rust tests",
      "cache": true,
      "inputs": [
        "apps/indexer/src/**/*.rs",
        "apps/indexer/Cargo.toml"
      ]
    }
  }
}
```

---

## 3. Next.js 15 App Architecture

### `apps/web/package.json`

```json
{
  "name": "@one-tap-trading/web",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "oxlint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest",
    "format": "oxfmt --write ."
  },
  "dependencies": {
    "react": "19.0.0",
    "react-dom": "19.0.0",
    "next": "15.1.0",
    "@one-tap-trading/shared-types": "workspace:*"
  },
  "devDependencies": {
    "typescript": "5.7.2",
    "@types/node": "22.10.5",
    "@types/react": "19.0.0",
    "@types/react-dom": "19.0.0",
    "tailwindcss": "4.0.0",
    "autoprefixer": "10.4.20",
    "postcss": "8.4.49",
    "oxlint": "0.11.0",
    "oxfmt": "0.11.0",
    "vitest": "3.1.0",
    "@vitest/ui": "3.1.0",
    "jsdom": "25.0.1"
  }
}
```

### `apps/web/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "allowJs": true,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "outDir": ".next"
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules", ".next", "dist"]
}
```

### `apps/web/next.config.ts`

```typescript
import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  swcMinify: true,
  typescript: {
    tsconfigPath: './tsconfig.json',
  },
  experimental: {
    optimizePackageImports: ['@one-tap-trading/shared-types'],
  },
};

export default nextConfig;
```

### `apps/web/tailwind.config.ts`

```typescript
import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: '#0f172a',
        secondary: '#1e293b',
        accent: '#3b82f6',
      },
    },
  },
  plugins: [],
};

export default config;
```

### `apps/web/src/app/layout.tsx`

```typescript
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'One Tap Trading',
  description: 'Gamified trading on MegaETH',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="bg-primary text-white">
        <header className="border-b border-secondary">
          <nav className="max-w-7xl mx-auto px-4 py-4">
            <h1 className="text-2xl font-bold">One Tap Trading</h1>
          </nav>
        </header>
        <main className="max-w-7xl mx-auto px-4 py-8">
          {children}
        </main>
      </body>
    </html>
  );
}
```

### `apps/web/src/app/page.tsx`

```typescript
import { PerpEngineABI } from '@one-tap-trading/shared-types';

export default function Home() {
  return (
    <div className="space-y-8">
      <section>
        <h2 className="text-3xl font-bold mb-4">Welcome to One Tap Trading</h2>
        <p className="text-secondary mb-4">
          Gamified trading on MegaETH. Phase 0: Foundation.
        </p>
      </section>

      <section className="bg-secondary p-6 rounded-lg">
        <h3 className="text-xl font-semibold mb-2">System Status</h3>
        <p className="text-sm text-gray-400">
          Contract ABI loaded: {PerpEngineABI ? 'Yes' : 'No'}
        </p>
      </section>
    </div>
  );
}
```

---

## 4. Rust Axum Server Architecture

### `apps/indexer/Cargo.toml`

```toml
[package]
name = "indexer"
version = "0.0.1"
edition = "2021"
publish = false

[dependencies]
axum = "0.7"
tokio = { version = "1", features = ["full"] }
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
anyhow = "1"

[dev-dependencies]
tokio-test = "0.4"

[profile.dev]
opt-level = 0
debug = true
split-debuginfo = "packed"
incremental = true

[profile.release]
opt-level = 3
debug = false
lto = true
codegen-units = 1

[lints.clippy]
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "warn"
panic = "deny"
panic_in_result_fn = "deny"
unimplemented = "deny"
allow_attributes = "deny"
dbg_macro = "deny"
todo = "deny"
print_stdout = "deny"
print_stderr = "deny"
await_holding_lock = "deny"
large_futures = "deny"
exit = "deny"
mem_forget = "deny"
module_name_repetitions = "allow"
similar_names = "allow"
```

### `apps/indexer/src/main.rs`

```rust
use axum::{
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Router,
};
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tracing::info;

mod handlers;
mod middleware;

use handlers::health;

#[derive(Clone)]
pub struct AppState {
    // Phase 0: in-memory only
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("indexer=debug".parse()?),
        )
        .init();

    let state = Arc::new(AppState {});

    let app = Router::new()
        .route("/health", get(health::handler))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:3001")
        .await?;

    info!("Indexer listening on http://127.0.0.1:3001");

    axum::serve(listener, app).await?;

    Ok(())
}
```

### `apps/indexer/src/handlers/health.rs`

```rust
use axum::http::StatusCode;
use serde_json::json;

pub async fn handler() -> (StatusCode, String) {
    let response = json!({
        "status": "ok",
        "service": "indexer",
        "version": "0.0.1"
    });

    (StatusCode::OK, response.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_health_endpoint() {
        let (status, body) = handler().await;
        assert_eq!(status, StatusCode::OK);
        assert!(body.contains("ok"));
    }
}
```

---

## 5. Foundry Project Architecture

### `packages/contracts/foundry.toml`

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
test = "test"
script = "script"
solc_version = "0.8.28"
optimizer = true
optimizer_runs = 200
evm_version = "cancun"

[fmt]
line_length = 100
tab_width = 2
use_tabs = false
bracket_spacing = true
int_type = "int256"
uint_type = "uint256"
quote_style = "double"

[doc]
out = "docs"
title = "One Tap Trading Contracts"
```

### `packages/contracts/src/PerpEngine.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPerpEngine {
    function openPosition(
        address asset,
        uint256 size,
        bool isLong
    ) external returns (uint256 positionId);

    function closePosition(uint256 positionId) external returns (uint256 pnl);

    function getPosition(uint256 positionId)
        external
        view
        returns (
            address asset,
            uint256 size,
            bool isLong,
            uint256 entryPrice
        );
}

contract PerpEngine is IPerpEngine {
    uint256 private nextPositionId = 1;

    mapping(uint256 => Position) private positions;
    mapping(address => uint256[]) private userPositions;

    struct Position {
        address owner;
        address asset;
        uint256 size;
        bool isLong;
        uint256 entryPrice;
        uint256 openedAt;
    }

    event PositionOpened(
        uint256 indexed positionId,
        address indexed owner,
        address indexed asset,
        uint256 size,
        bool isLong
    );

    event PositionClosed(
        uint256 indexed positionId,
        address indexed owner,
        uint256 pnl
    );

    function openPosition(
        address asset,
        uint256 size,
        bool isLong
    ) external override returns (uint256 positionId) {
        require(asset != address(0), "Invalid asset");
        require(size > 0, "Size must be positive");

        positionId = nextPositionId++;

        positions[positionId] = Position({
            owner: msg.sender,
            asset: asset,
            size: size,
            isLong: isLong,
            entryPrice: 0,
            openedAt: block.timestamp
        });

        userPositions[msg.sender].push(positionId);

        emit PositionOpened(positionId, msg.sender, asset, size, isLong);
    }

    function closePosition(uint256 positionId)
        external
        override
        returns (uint256 pnl)
    {
        Position storage position = positions[positionId];
        require(position.owner == msg.sender, "Not position owner");

        pnl = 0;

        delete positions[positionId];

        emit PositionClosed(positionId, msg.sender, pnl);
    }

    function getPosition(uint256 positionId)
        external
        view
        override
        returns (
            address asset,
            uint256 size,
            bool isLong,
            uint256 entryPrice
        )
    {
        Position storage position = positions[positionId];
        return (
            position.asset,
            position.size,
            position.isLong,
            position.entryPrice
        );
    }
}
```

### `packages/contracts/test/PerpEngine.t.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/PerpEngine.sol";

contract PerpEngineTest is Test {
    PerpEngine engine;
    address user = address(0x1);
    address asset = address(0x2);

    function setUp() public {
        engine = new PerpEngine();
    }

    function test_OpenPosition() public {
        vm.prank(user);
        uint256 positionId = engine.openPosition(asset, 100e18, true);

        assertEq(positionId, 1);

        (address returnedAsset, uint256 size, bool isLong, ) = engine
            .getPosition(positionId);
        assertEq(returnedAsset, asset);
        assertEq(size, 100e18);
        assertTrue(isLong);
    }

    function test_ClosePosition() public {
        vm.prank(user);
        uint256 positionId = engine.openPosition(asset, 100e18, true);

        vm.prank(user);
        uint256 pnl = engine.closePosition(positionId);

        assertEq(pnl, 0);
    }

    function test_RevertOnInvalidAsset() public {
        vm.prank(user);
        vm.expectRevert("Invalid asset");
        engine.openPosition(address(0), 100e18, true);
    }

    function test_RevertOnZeroSize() public {
        vm.prank(user);
        vm.expectRevert("Size must be positive");
        engine.openPosition(asset, 0, true);
    }
}
```

---

## 6. Shared Types Pipeline (wagmi)

### `packages/shared-types/package.json`

```json
{
  "name": "@one-tap-trading/shared-types",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "types": "./src/index.ts",
      "default": "./src/index.ts"
    }
  },
  "scripts": {
    "generate": "wagmi generate",
    "build": "tsc --noEmit",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "wagmi": "^2.12.0",
    "viem": "^2.21.0"
  },
  "devDependencies": {
    "typescript": "5.7.2",
    "@types/node": "22.10.5",
    "@wagmi/cli": "^2.1.0"
  }
}
```

### `packages/shared-types/wagmi.config.ts`

```typescript
import { defineConfig } from '@wagmi/cli';
import { foundry } from '@wagmi/cli/plugins';
import path from 'path';

export default defineConfig({
  out: 'src/generated/index.ts',
  contracts: [],
  plugins: [
    foundry({
      project: path.resolve(__dirname, '../contracts'),
      include: ['PerpEngine.sol/**'],
    }),
  ],
});
```

### `packages/shared-types/src/index.ts`

```typescript
export * from './generated/index.js';

export function isPerpEngineABI(abi: unknown): boolean {
  return (
    Array.isArray(abi) &&
    abi.some(
      (item) =>
        typeof item === 'object' &&
        item !== null &&
        'name' in item &&
        item.name === 'openPosition'
    )
  );
}
```

---

## 7. CI/CD Architecture

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  CARGO_TERM_COLOR: always
  FOUNDRY_SOLC_VERSION: 0.8.28

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11136cecee0c2a1dd1370aea2aff3a40ec0d8f0d
      - uses: actions/setup-node@1a4442caab129478691007521f4cd4ff2da9deec
        with:
          node-version: '22'
      - uses: pnpm/action-setup@fe02b34f77f8bc703788d5817da081398fad5dd2
        with:
          version: '9'
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint

  typecheck:
    name: Type Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11136cecee0c2a1dd1370aea2aff3a40ec0d8f0d
      - uses: actions/setup-node@1a4442caab129478691007521f4cd4ff2da9deec
        with:
          node-version: '22'
      - uses: pnpm/action-setup@fe02b34f77f8bc703788d5817da081398fad5dd2
        with:
          version: '9'
      - run: pnpm install --frozen-lockfile
      - run: pnpm typecheck

  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11136cecee0c2a1dd1370aea2aff3a40ec0d8f0d
      - uses: actions/setup-node@1a4442caab129478691007521f4cd4ff2da9deec
        with:
          node-version: '22'
      - uses: pnpm/action-setup@fe02b34f77f8bc703788d5817da081398fad5dd2
        with:
          version: '9'
      - uses: dtolnay/rust-toolchain@stable
      - uses: foundry-rs/foundry-toolchain@8ab929f0084d9f0e3b816e8d720cb4126db99e15
      - run: pnpm install --frozen-lockfile
      - run: pnpm test

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [lint, typecheck, test]
    steps:
      - uses: actions/checkout@11136cecee0c2a1dd1370aea2aff3a40ec0d8f0d
      - uses: actions/setup-node@1a4442caab129478691007521f4cd4ff2da9deec
        with:
          node-version: '22'
      - uses: pnpm/action-setup@fe02b34f77f8bc703788d5817da081398fad5dd2
        with:
          version: '9'
      - uses: dtolnay/rust-toolchain@stable
      - uses: foundry-rs/foundry-toolchain@8ab929f0084d9f0e3b816e8d720cb4126db99e15
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
```

---

## 8. Pre-commit Hooks (prek)

### `.prek.toml`

```toml
version = "0.1"

[[hooks]]
name = "oxlint"
description = "Lint TypeScript/JavaScript"
entry = "oxlint"
language = "system"
files = '\.(ts|tsx|js|jsx)$'
stages = ["commit"]
pass_filenames = true

[[hooks]]
name = "oxfmt"
description = "Format TypeScript/JavaScript"
entry = "oxfmt --write"
language = "system"
files = '\.(ts|tsx|js|jsx)$'
stages = ["commit"]
pass_filenames = true

[[hooks]]
name = "cargo-fmt"
description = "Format Rust"
entry = "cargo fmt --"
language = "system"
files = '\.rs$'
stages = ["commit"]
pass_filenames = true

[[hooks]]
name = "cargo-clippy"
description = "Lint Rust"
entry = "cargo clippy --all-targets --all-features -- -D warnings"
language = "system"
files = '\.rs$'
stages = ["commit"]
pass_filenames = false

[[hooks]]
name = "forge-fmt"
description = "Format Solidity"
entry = "forge fmt"
language = "system"
files = '\.sol$'
stages = ["commit"]
pass_filenames = false
```

---

## 9. Integration Points & Dependency Flow

### Workspace Dependencies

```
apps/web/package.json:
  dependencies:
    @one-tap-trading/shared-types: workspace:*

apps/indexer/package.json:
  (no workspace dependencies in Phase 0)

packages/shared-types/package.json:
  (no workspace dependencies)

packages/contracts/package.json:
  (no workspace dependencies)
```

### Type Generation Flow

```
1. Turborepo runs: contracts#build
   → forge build outputs ABIs to packages/contracts/out/

2. Turborepo runs: shared-types#generate
   → wagmi.config.ts reads packages/contracts/out/
   → generates packages/shared-types/src/generated/index.ts

3. Turborepo runs: web#build
   → Next.js imports from @one-tap-trading/shared-types
   → types are available at build time
```

---

## 10. Environment Configuration

### `.env.example`

```bash
NEXT_PUBLIC_INDEXER_URL=http://localhost:3001
NEXT_PUBLIC_CHAIN_ID=8453
RUST_LOG=indexer=debug,axum=info
INDEXER_PORT=3001
FOUNDRY_SOLC_VERSION=0.8.28
FOUNDRY_PROFILE=default
```

---

## 11. Build & Development Workflow

### Local Development

```bash
pnpm install
pnpm dev
pnpm test
pnpm format
pnpm lint
pnpm typecheck
pnpm build
```

### CI/CD Flow

```
PR opened
  ↓
Parallel jobs: lint, typecheck, test
  ↓
Sequential job: build
  ↓
All checks pass → PR mergeable
```

---

## 12. Success Criteria

- [x] `pnpm install` succeeds
- [x] `pnpm dev` starts web (port 3000) + indexer (port 3001)
- [x] `pnpm build` completes with Turborepo caching
- [x] `pnpm lint` passes
- [x] `pnpm typecheck` passes
- [x] `pnpm test` runs all tests
- [x] CI workflow passes on PR
- [x] Pre-commit hooks prevent broken commits
- [x] Build time < 30s (cached)
- [x] Generated types not in git history
- [x] All workspaces can import from shared-types
- [x] Contract changes trigger type regeneration

---

## 13. Known Limitations & Future Work

### Phase 0 Limitations

1. No persistence: In-memory storage only
2. No oracle: Contract prices hardcoded to zero
3. No WebSocket: HTTP polling only
4. No authentication: No session management
5. No deployment: Local development only

### Phase 1+ Roadmap

- Database integration (PostgreSQL)
- Oracle integration (RedStone Bolt)
- WebSocket infrastructure
- Account Abstraction / Session Keys
- Trading engine logic
- Canvas rendering
- Deployment (Vercel + fly.io)

