#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
ALTO_CONFIG="$ROOT/tools/alto/megaeth-carrot.json"
ALTO_CLI="${ALTO_PATH:-/tools/alto/src/esm/cli/index.js}"

if [[ ! -f "$ENV_FILE" ]]; then
	echo "error: .env not found — run: cp .env.example .env" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${DEPLOYER_PRIVATE_KEY:-}" ]]; then
	echo "error: DEPLOYER_PRIVATE_KEY is not set in .env" >&2
	exit 1
fi

ALTO_PID=""

start_alto() {
	if [[ ! -f "$ALTO_CLI" ]]; then
		echo "warn: Alto not found at $ALTO_CLI — trades will not work" >&2
		echo "      set ALTO_PATH env var or see tools/alto/README.md" >&2
		return
	fi

	node "$ALTO_CLI" \
		--config "$ALTO_CONFIG" \
		--executor-private-keys "$DEPLOYER_PRIVATE_KEY" \
		--utility-private-key "$DEPLOYER_PRIVATE_KEY" \
		2>&1 | sed 's/^/[alto] /' &

	ALTO_PID=$!
	echo "[dev] Alto bundler → http://localhost:4337 (pid $ALTO_PID)"
}

cleanup() {
	if [[ -n "$ALTO_PID" ]]; then
		kill "$ALTO_PID" 2>/dev/null || true
	fi
}
trap cleanup EXIT INT TERM

start_alto

cd "$ROOT"
exec pnpm dev
