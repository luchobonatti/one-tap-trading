import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type StoredSession = {
  validUntil: number;
};

type E2EState = {
  serializedValidator: string;
  sessionKey: StoredSession;
  accountAddress: string;
};

function isValidState(state: unknown): state is E2EState {
  if (typeof state !== "object" || state === null) {
    return false;
  }

  const s = state as Record<string, unknown>;

  if (typeof s.serializedValidator !== "string") {
    return false;
  }

  if (typeof s.sessionKey !== "object" || s.sessionKey === null) {
    return false;
  }

  const sessionKey = s.sessionKey as Record<string, unknown>;
  if (
    typeof sessionKey.validUntil !== "number" ||
    Number.isNaN(sessionKey.validUntil)
  ) {
    return false;
  }

  return typeof s.accountAddress === "string";
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

  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(statePath, "utf-8"));
  } catch {
    console.error(
      "\n❌ e2e/state.json is malformed. Re-run: pnpm test:e2e:setup\n",
    );
    process.exit(1);
  }

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
