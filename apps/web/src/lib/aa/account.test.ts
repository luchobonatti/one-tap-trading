import { describe, it, expect, beforeEach, vi } from "vitest";
import { hasStoredAccount, clearPasskeyAccount } from "@/lib/aa/account";

beforeEach(() => {
  localStorage.clear();
  vi.clearAllMocks();
});

describe("hasStoredAccount", () => {
  it("returns false when nothing stored", () => {
    expect(hasStoredAccount()).toBe(false);
  });

  it("returns true when serialized validator is present", () => {
    localStorage.setItem("ott-validator-v1", "some-serialized-data");
    expect(hasStoredAccount()).toBe(true);
  });
});

describe("clearPasskeyAccount", () => {
  it("removes serialized validator from storage", () => {
    localStorage.setItem("ott-validator-v1", "some-serialized-data");
    clearPasskeyAccount();
    expect(hasStoredAccount()).toBe(false);
  });
});
