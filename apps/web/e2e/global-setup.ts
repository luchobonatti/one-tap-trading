import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

type StoredSession = {
  validUntil: number;
};

type E2EState = {
  serializedValidator: string;
  sessionKey: StoredSession;
  accountAddress: string;
};

function isValidState(state: unknown): state is E2EState {
  return (
    typeof state === "object" &&
    state !== null &&
    "serializedValidator" in state &&
    typeof (state as Record<string, unknown>).serializedValidator === "string" &&
    "sessionKey" in state &&
    typeof (state as Record<string, unknown>).sessionKey === "object" &&
    "accountAddress" in state &&
    typeof (state as Record<string, unknown>).accountAddress === "string"
  );
}

export default function globalSetup(): void {
  const statePath = resolve(__dirname, "state.json");

  if (!existsSync(statePath)) {
    console.error(
      "\n❌ E2E state not found. Run: pnpm test:e2e:setup\n" +
        "   This creates e2e/state.json with a funded testnet account.\n",
    );
    process.exit(1);
  }

  const raw: unknown = JSON.parse(readFileSync(statePath, "utf-8"));

  if (!isValidState(raw)) {
    console.error(
      "\n❌ e2e/state.json is malformed. Re-run: pnpm test:e2e:setup\n",
    );
    process.exit(1);
  }

  const bufferSeconds = 300;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (raw.sessionKey.validUntil < nowSeconds + bufferSeconds) {
    console.error(
      "\n❌ E2E session key expired (or expires in <5min).\n" +
        "   Re-run: pnpm test:e2e:setup\n",
    );
    process.exit(1);
  }

  const expiresIn = raw.sessionKey.validUntil - nowSeconds;
  const expiresInMinutes = Math.floor(expiresIn / 60);
  console.log(
    `\n✅ E2E state loaded — account: ${raw.accountAddress}\n` +
      `   Session expires in ${expiresInMinutes} minutes\n`,
  );
}
