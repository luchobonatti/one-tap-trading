import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test as base, type Page } from "@playwright/test";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

type StoredSession = {
  privateKey: `0x${string}`;
  address: `0x${string}`;
  validUntil: number;
};

type E2EState = {
  serializedValidator: string;
  sessionKey: StoredSession;
  accountAddress: `0x${string}`;
};

function loadState(): E2EState {
  return JSON.parse(
    readFileSync(resolve(__dirname, "state.json"), "utf-8"),
  ) as E2EState;
}

export const test = base.extend<{ authenticatedPage: Page }>({
  authenticatedPage: async ({ page }, use) => {
    const state = loadState();

    await page.addInitScript((s: E2EState) => {
      localStorage.setItem("ott-validator-v1", s.serializedValidator);
      sessionStorage.setItem("ott-session-key-v1", JSON.stringify(s.sessionKey));
    }, state);

    await page.goto("/");
    await use(page);
  },
});

export { expect } from "@playwright/test";
