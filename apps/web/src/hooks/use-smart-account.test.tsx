import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { useSmartAccount } from "@/hooks/use-smart-account";

vi.mock("@/lib/aa/account", () => ({
  loadPasskeyAccount: vi.fn(),
  createPasskeyAccount: vi.fn(),
}));

import { loadPasskeyAccount, createPasskeyAccount } from "@/lib/aa/account";

const mockLoad = vi.mocked(loadPasskeyAccount);
const mockCreate = vi.mocked(createPasskeyAccount);

beforeEach(() => {
  vi.clearAllMocks();
  localStorage.clear();
});

describe("useSmartAccount", () => {
  it("starts in loading state then moves to idle when no account stored", async () => {
    mockLoad.mockResolvedValue(null);
    const { result } = renderHook(() => useSmartAccount());

    expect(result.current.status).toBe("loading");

    await waitFor(() => {
      expect(result.current.status).toBe("idle");
    });

    expect(result.current.address).toBeUndefined();
    expect(result.current.isReady).toBe(false);
  });

  it("moves to ready when stored account exists", async () => {
    const mockAddress = "0xabc123" as `0x${string}`;
    mockLoad.mockResolvedValue({ address: mockAddress });

    const { result } = renderHook(() => useSmartAccount());

    await waitFor(() => {
      expect(result.current.status).toBe("ready");
    });

    expect(result.current.address).toBe(mockAddress);
    expect(result.current.isReady).toBe(true);
  });

  it("transitions creating -> ready on successful create()", async () => {
    mockLoad.mockResolvedValue(null);
    const mockAddress = "0xdef456" as `0x${string}`;
    mockCreate.mockResolvedValue({ address: mockAddress });

    const { result } = renderHook(() => useSmartAccount());

    await waitFor(() => expect(result.current.status).toBe("idle"));

    await act(async () => {
      await result.current.create();
    });

    expect(result.current.status).toBe("ready");
    expect(result.current.address).toBe(mockAddress);
    expect(result.current.isReady).toBe(true);
  });

  it("transitions creating -> error on failed create()", async () => {
    mockLoad.mockResolvedValue(null);
    mockCreate.mockRejectedValue(new Error("Passkey registration cancelled"));

    const { result } = renderHook(() => useSmartAccount());

    await waitFor(() => expect(result.current.status).toBe("idle"));

    await act(async () => {
      await result.current.create();
    });

    expect(result.current.status).toBe("error");
    expect(result.current.error).toBe("Passkey registration cancelled");
    expect(result.current.isReady).toBe(false);
  });
});
