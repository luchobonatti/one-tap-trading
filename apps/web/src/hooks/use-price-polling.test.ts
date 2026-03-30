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
  vi.restoreAllMocks();
});

describe("usePricePolling", () => {
  it("fetches price immediately on mount and writes to priceRef", async () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);

    const renderCount = { current: 0 };
    const { result } = renderHook(() => {
      renderCount.current += 1;
      return usePricePolling(500);
    });

    const initialRenders = renderCount.current;

    await act(() => vi.advanceTimersByTimeAsync(0));

    expect(result.current.priceRef.current).toBe(2000_00000000n);
    expect(result.current.price).toBe(2000_00000000n);
    expect(renderCount.current).toBe(initialRenders + 1);
  });

  it("starts as not stale", () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);
    const { result } = renderHook(() => usePricePolling(500));
    expect(result.current.stale).toBe(false);
  });

  it("becomes stale after 3 consecutive errors", async () => {
    mockReadContract.mockRejectedValue(new Error("rpc fail"));

    const { result } = renderHook(() => usePricePolling(500));

    await act(() => vi.advanceTimersByTimeAsync(0));
    await act(() => vi.advanceTimersByTimeAsync(500));
    await act(() => vi.advanceTimersByTimeAsync(500));

    expect(result.current.stale).toBe(true);
  });

  it("resets stale after successful fetch", async () => {
    const threeFailures = [
      new Error("fail"),
      new Error("fail"),
      new Error("fail"),
    ] as const;
    mockReadContract
      .mockRejectedValueOnce(threeFailures[0])
      .mockRejectedValueOnce(threeFailures[1])
      .mockRejectedValueOnce(threeFailures[2])
      .mockResolvedValue([2000_00000000n] as unknown as never);

    const { result } = renderHook(() => usePricePolling(500));

    await act(() => vi.advanceTimersByTimeAsync(0));
    await act(() => vi.advanceTimersByTimeAsync(500));
    await act(() => vi.advanceTimersByTimeAsync(500));

    expect(result.current.stale).toBe(true);

    await act(() => vi.advanceTimersByTimeAsync(500));

    expect(result.current.stale).toBe(false);
  });

  it("clears timeout on unmount", () => {
    mockReadContract.mockResolvedValue([2000_00000000n] as unknown as never);
    const clearSpy = vi.spyOn(globalThis, "clearTimeout");

    const { unmount } = renderHook(() => usePricePolling(500));
    unmount();

    expect(clearSpy).toHaveBeenCalled();
  });
});
