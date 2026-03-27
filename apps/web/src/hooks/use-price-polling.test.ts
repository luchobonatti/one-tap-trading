import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { usePricePolling } from "@/hooks/use-price-polling";

vi.mock("@/lib/aa/client", () => ({
  publicClient: {
    readContract: vi.fn(),
  },
}));

import { publicClient } from "@/lib/aa/client";

const mockReadContract = vi.mocked(publicClient.readContract);

beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("usePricePolling", () => {
  it("writes price to priceRef without causing re-renders", async () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);

    const renderCount = { current: 0 };
    const { result } = renderHook(() => {
      renderCount.current += 1;
      return usePricePolling(500);
    });

    const initialRenders = renderCount.current;

    await act(async () => {
      vi.advanceTimersByTime(500);
      await Promise.resolve();
    });

    expect(result.current.priceRef.current).toBe(2000_00000000n);
    expect(renderCount.current).toBe(initialRenders);
  });

  it("starts as not stale", () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);
    const { result } = renderHook(() => usePricePolling(500));
    expect(result.current.stale).toBe(false);
  });

  it("becomes stale after 3 consecutive errors", async () => {
    mockReadContract.mockRejectedValue(new Error("rpc fail"));

    const { result } = renderHook(() => usePricePolling(500));

    for (let i = 0; i < 3; i++) {
      await act(async () => {
        vi.advanceTimersByTime(500);
        await Promise.resolve();
        await Promise.resolve();
      });
    }

    expect(result.current.stale).toBe(true);
  });

  it("resets stale after successful fetch", async () => {
    mockReadContract
      .mockRejectedValueOnce(new Error("fail"))
      .mockRejectedValueOnce(new Error("fail"))
      .mockRejectedValueOnce(new Error("fail"))
      .mockResolvedValue([2000_00000000n] as unknown as never);

    const { result } = renderHook(() => usePricePolling(500));

    for (let i = 0; i < 3; i++) {
      await act(async () => {
        vi.advanceTimersByTime(500);
        await Promise.resolve();
        await Promise.resolve();
      });
    }

    expect(result.current.stale).toBe(true);

    await act(async () => {
      vi.advanceTimersByTime(500);
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(result.current.stale).toBe(false);
  });

  it("clears interval on unmount", () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);
    const clearSpy = vi.spyOn(globalThis, "clearInterval");

    const { unmount } = renderHook(() => usePricePolling(500));
    unmount();

    expect(clearSpy).toHaveBeenCalled();
  });
});
