import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { Hex } from "viem";
import { renderHook, act, waitFor } from "@testing-library/react";
import { useSessionKey } from "@/hooks/use-session-key";

vi.mock("@/lib/aa/session-key", () => ({
  delegateSessionKey: vi.fn(),
  loadSessionKey: vi.fn(),
  hasSessionKey: vi.fn(),
  isSessionExpired: vi.fn(),
  clearSessionKey: vi.fn(),
  sessionExpiresAt: vi.fn(),
}));

import {
  delegateSessionKey,
  loadSessionKey,
  hasSessionKey,
  isSessionExpired,
  clearSessionKey,
  sessionExpiresAt,
} from "@/lib/aa/session-key";

const mockDelegate = vi.mocked(delegateSessionKey);
const mockLoad = vi.mocked(loadSessionKey);
const mockHas = vi.mocked(hasSessionKey);
const mockExpired = vi.mocked(isSessionExpired);
const mockClear = vi.mocked(clearSessionKey);
const mockExpiresAt = vi.mocked(sessionExpiresAt);

const MOCK_SESSION = {
  privateKey:
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex,
  address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`,
  validUntil: Math.floor(Date.now() / 1000) + 3600,
  validatorAddress: "0xD06fbb9f82e9EC3957a9D57E61f3fb5966a6195e" as `0x${string}`,
};

beforeEach(() => {
  vi.clearAllMocks();
  mockHas.mockReturnValue(false);
  mockLoad.mockReturnValue(null);
  mockExpired.mockReturnValue(false);
  mockExpiresAt.mockReturnValue(new Date(Date.now() + 3_600_000));
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("useSessionKey", () => {
  it("starts idle when account not ready", () => {
    const { result } = renderHook(() => useSessionKey(false));
    expect(result.current.status).toBe("idle");
    expect(result.current.isReady).toBe(false);
  });

  it("starts idle when account ready but no session stored", () => {
    mockHas.mockReturnValue(false);
    const { result } = renderHook(() => useSessionKey(true));
    expect(result.current.status).toBe("idle");
  });

  it("detects ready session on mount", () => {
    mockHas.mockReturnValue(true);
    mockLoad.mockReturnValue(MOCK_SESSION);
    mockExpired.mockReturnValue(false);
    const { result } = renderHook(() => useSessionKey(true));
    expect(result.current.status).toBe("ready");
    expect(result.current.isReady).toBe(true);
  });

  it("detects expired session on mount", () => {
    mockHas.mockReturnValue(true);
    mockLoad.mockReturnValue({ ...MOCK_SESSION, validUntil: 0 });
    mockExpired.mockReturnValue(true);
    const { result } = renderHook(() => useSessionKey(true));
    expect(result.current.status).toBe("expired");
  });

  it("transitions delegating -> ready on successful delegate()", async () => {
    mockHas.mockReturnValue(false);
    mockDelegate.mockResolvedValue("0xabc" as `0x${string}`);
    mockLoad.mockReturnValue(MOCK_SESSION);

    const { result } = renderHook(() => useSessionKey(true));

    await act(async () => {
      await result.current.delegate("100");
    });

    expect(result.current.status).toBe("ready");
    expect(result.current.isReady).toBe(true);
  });

  it("transitions delegating -> error on failed delegate()", async () => {
    mockHas.mockReturnValue(false);
    mockDelegate.mockRejectedValue(new Error("Passkey cancelled"));

    const { result } = renderHook(() => useSessionKey(true));

    await act(async () => {
      await result.current.delegate("100");
    });

    expect(result.current.status).toBe("error");
    expect(result.current.error).toBe("Passkey cancelled");
    expect(result.current.isReady).toBe(false);
  });

  it("revoke() clears session and resets to idle", async () => {
    mockHas.mockReturnValue(true);
    mockLoad.mockReturnValue(MOCK_SESSION);
    mockExpired.mockReturnValue(false);

    const { result } = renderHook(() => useSessionKey(true));

    await waitFor(() => expect(result.current.status).toBe("ready"));

    act(() => {
      result.current.revoke();
    });

    expect(mockClear).toHaveBeenCalledOnce();
    expect(result.current.status).toBe("idle");
    expect(result.current.expiresAt).toBeUndefined();
  });
});
