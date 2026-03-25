import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useTrade } from "@/hooks/use-trade";

vi.mock("@/lib/trading/submit", () => ({
  openTrade: vi.fn(),
  waitForOp: vi.fn(),
}));

import { openTrade, waitForOp } from "@/lib/trading/submit";

const mockOpenTrade = vi.mocked(openTrade);
const mockWaitForOp = vi.mocked(waitForOp);

const ACCOUNT = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`;

beforeEach(() => {
  vi.clearAllMocks();
});

describe("useTrade", () => {
  it("starts in idle state", () => {
    const { result } = renderHook(() => useTrade(ACCOUNT));
    expect(result.current.status).toBe("idle");
    expect(result.current.pendingOpHash).toBeUndefined();
    expect(result.current.error).toBeUndefined();
  });

  it("transitions idle → pending → confirmed on successful trade", async () => {
    mockOpenTrade.mockResolvedValue("0xophash123" as `0x${string}`);
    mockWaitForOp.mockResolvedValue(undefined);

    const { result } = renderHook(() => useTrade(ACCOUNT));

    const tradePromise = act(async () => {
      await result.current.openPosition(true, 5n);
    });

    await tradePromise;

    expect(result.current.status).toBe("confirmed");
    expect(result.current.pendingOpHash).toBe("0xophash123");
    expect(result.current.error).toBeUndefined();
  });

  it("transitions idle → pending → failed when openTrade throws", async () => {
    mockOpenTrade.mockRejectedValue(new Error("Session key expired"));
    mockWaitForOp.mockResolvedValue(undefined);

    const { result } = renderHook(() => useTrade(ACCOUNT));

    await act(async () => {
      await result.current.openPosition(false, 10n);
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe("Session key expired");
  });

  it("transitions pending → failed when waitForOp throws", async () => {
    mockOpenTrade.mockResolvedValue("0xhash" as `0x${string}`);
    mockWaitForOp.mockRejectedValue(new Error("UserOp reverted"));

    const { result } = renderHook(() => useTrade(ACCOUNT));

    await act(async () => {
      await result.current.openPosition(true, 2n);
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe("UserOp reverted");
  });

  it("fails immediately when accountAddress is undefined", async () => {
    const { result } = renderHook(() => useTrade(undefined));

    await act(async () => {
      await result.current.openPosition(true, 5n);
    });

    expect(result.current.status).toBe("failed");
    expect(result.current.error).toBe("Smart account not ready");
    expect(mockOpenTrade).not.toHaveBeenCalled();
  });

  it("reset() returns to idle state", async () => {
    mockOpenTrade.mockRejectedValue(new Error("fail"));
    const { result } = renderHook(() => useTrade(ACCOUNT));

    await act(async () => {
      await result.current.openPosition(true, 5n);
    });
    expect(result.current.status).toBe("failed");

    act(() => {
      result.current.reset();
    });

    expect(result.current.status).toBe("idle");
    expect(result.current.error).toBeUndefined();
  });
});
