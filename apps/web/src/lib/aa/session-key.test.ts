import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  loadSessionKey,
  hasSessionKey,
  isSessionExpired,
  clearSessionKey,
  sessionExpiresAt,
} from "@/lib/aa/session-key";
import type { StoredSession } from "@/lib/aa/session-key";
import { sessionKeyValidatorAddress } from "@one-tap/shared-types";

const STORAGE_KEY = "ott-session-key-v5";
const VALIDATOR_ADDR = sessionKeyValidatorAddress[6343];

const MOCK_SESSION: StoredSession = {
  privateKey:
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  validUntil: Math.floor(Date.now() / 1000) + 3600,
  validatorAddress: VALIDATOR_ADDR,
};

const EXPIRED_SESSION: StoredSession = {
  ...MOCK_SESSION,
  validUntil: Math.floor(Date.now() / 1000) - 1,
};

beforeEach(() => {
  sessionStorage.clear();
  vi.clearAllMocks();
});

describe("session key storage", () => {
  it("hasSessionKey returns false when nothing stored", () => {
    expect(hasSessionKey()).toBe(false);
  });

  it("hasSessionKey returns true after storing", () => {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(MOCK_SESSION));
    expect(hasSessionKey()).toBe(true);
  });

  it("loadSessionKey returns null when nothing stored", () => {
    expect(loadSessionKey()).toBeNull();
  });

  it("loadSessionKey returns stored session", () => {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(MOCK_SESSION));
    const loaded = loadSessionKey();
    expect(loaded).not.toBeNull();
    expect(loaded?.address).toBe(MOCK_SESSION.address);
    expect(loaded?.validUntil).toBe(MOCK_SESSION.validUntil);
  });

  it("loadSessionKey returns null and clears stale session with wrong validator", () => {
    const stale: StoredSession = {
      ...MOCK_SESSION,
      validatorAddress: "0x0000000000000000000000000000000000000001",
    };
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(stale));
    expect(loadSessionKey()).toBeNull();
    expect(sessionStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  it("loadSessionKey returns null on corrupted data", () => {
    sessionStorage.setItem(STORAGE_KEY, "{invalid json{{");
    expect(loadSessionKey()).toBeNull();
  });

  it("clearSessionKey removes the stored session", () => {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(MOCK_SESSION));
    clearSessionKey();
    expect(hasSessionKey()).toBe(false);
    expect(loadSessionKey()).toBeNull();
  });
});

describe("session expiry", () => {
  it("isSessionExpired returns false for future session", () => {
    expect(isSessionExpired(MOCK_SESSION)).toBe(false);
  });

  it("isSessionExpired returns true for past validUntil", () => {
    expect(isSessionExpired(EXPIRED_SESSION)).toBe(true);
  });

  it("sessionExpiresAt returns correct Date from validUntil", () => {
    const date = sessionExpiresAt(MOCK_SESSION);
    expect(date.getTime()).toBe(MOCK_SESSION.validUntil * 1000);
  });
});
