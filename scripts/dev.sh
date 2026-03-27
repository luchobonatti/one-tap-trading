#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
	echo "error: .env not found — run: cp .env.example .env" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${NEXT_PUBLIC_BUNDLER_RPC_URL:-}" ]]; then
	echo "error: NEXT_PUBLIC_BUNDLER_RPC_URL is not set in .env" >&2
	echo "       Get a ZeroDev project at https://dashboard.zerodev.app" >&2
	exit 1
fi

echo "[dev] Bundler → $NEXT_PUBLIC_BUNDLER_RPC_URL"

cd "$ROOT"
exec pnpm dev
