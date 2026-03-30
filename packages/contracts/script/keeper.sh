#!/usr/bin/env bash
# Refreshes MockPriceFeed._updatedAt every 2 s so PriceOracle.getPrice()
# never hits the 5-second STALENESS_THRESHOLD on testnet.
#
# Usage (from repo root):
#   source packages/contracts/.env && bash packages/contracts/script/keeper.sh
#
# Stops on Ctrl-C.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../.env"
if [[ -f "$ENV_FILE" ]]; then
	# shellcheck source=/dev/null
	source "$ENV_FILE"
fi

FEED="0xd152AaBf6e4dA27004dC4a4B29da4a7754318469"
INTERVAL=2

echo "Keeper started — refreshing MockPriceFeed every ${INTERVAL}s. Ctrl-C to stop."

while true; do
	CURRENT_PRICE=$(cast call "$FEED" "latestAnswer()(int256,uint256)" --rpc-url "$MEGAETH_RPC_URL" | head -1)
	cast send "$FEED" "setPrice(int256)" "$CURRENT_PRICE" \
		--rpc-url "$MEGAETH_RPC_URL" \
		--private-key "$DEPLOYER_PRIVATE_KEY" \
		--legacy \
		--quiet
	echo "$(date -u +%H:%M:%S)  price=$CURRENT_PRICE"
	sleep "$INTERVAL"
done
