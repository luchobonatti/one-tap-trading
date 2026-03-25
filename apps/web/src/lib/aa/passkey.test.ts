import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  storeWebAuthnKey,
  loadWebAuthnKey,
  clearWebAuthnKey,
  hasStoredPasskey,
} from "@/lib/aa/passkey";
import type { WebAuthnKey } from "@zerodev/webauthn-key";

const MOCK_KEY: WebAuthnKey = {
  pubX: 123456789n,
  pubY: 987654321n,
  authenticatorId: "dGVzdC1jcmVkZW50aWFsLWlk",
  authenticatorIdHash:
    "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
  rpID: "localhost",
};

describe("passkey storage", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
  });

  it("hasStoredPasskey returns false when nothing stored", () => {
    expect(hasStoredPasskey()).toBe(false);
  });

  it("hasStoredPasskey returns true after storing", () => {
    storeWebAuthnKey(MOCK_KEY);
    expect(hasStoredPasskey()).toBe(true);
  });

  it("round-trips WebAuthnKey through localStorage", () => {
    storeWebAuthnKey(MOCK_KEY);
    const loaded = loadWebAuthnKey();
    expect(loaded).not.toBeNull();
    expect(loaded?.pubX).toBe(MOCK_KEY.pubX);
    expect(loaded?.pubY).toBe(MOCK_KEY.pubY);
    expect(loaded?.authenticatorId).toBe(MOCK_KEY.authenticatorId);
    expect(loaded?.authenticatorIdHash).toBe(MOCK_KEY.authenticatorIdHash);
    expect(loaded?.rpID).toBe(MOCK_KEY.rpID);
  });

  it("loadWebAuthnKey returns null when nothing stored", () => {
    expect(loadWebAuthnKey()).toBeNull();
  });

  it("clearWebAuthnKey removes the stored key", () => {
    storeWebAuthnKey(MOCK_KEY);
    clearWebAuthnKey();
    expect(hasStoredPasskey()).toBe(false);
    expect(loadWebAuthnKey()).toBeNull();
  });

  it("loadWebAuthnKey returns null on corrupted data", () => {
    localStorage.setItem("ott-passkey-v1", "not-valid-json{{{");
    expect(loadWebAuthnKey()).toBeNull();
  });

  it("bigint serialization preserves large values", () => {
    const largeKey: WebAuthnKey = {
      ...MOCK_KEY,
      pubX: BigInt(
        "0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC",
      ),
      pubY: BigInt(
        "0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B",
      ),
    };
    storeWebAuthnKey(largeKey);
    const loaded = loadWebAuthnKey();
    expect(loaded?.pubX).toBe(largeKey.pubX);
    expect(loaded?.pubY).toBe(largeKey.pubY);
  });
});
