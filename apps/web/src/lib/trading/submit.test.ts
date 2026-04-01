import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  getCurrentPriceBounds,
  openTrade,
  closeTrade,
} from "@/lib/trading/submit";

vi.mock("@/lib/aa/client", () => ({
  publicClient: {
    readContract: vi.fn(),
    getBlock: vi.fn(),
  },
  estimateFeesPerGas: vi.fn(),
}));

vi.mock("@/lib/aa/account", () => ({
  getSmartAccountClient: vi.fn().mockResolvedValue({
    sendUserOperation: vi.fn().mockResolvedValue("0xophash"),
  }),
}));

vi.mock("@/lib/aa/session-key", () => ({
  loadSessionKey: vi.fn(),
  isSessionExpired: vi.fn(),
}));

import { publicClient } from "@/lib/aa/client";
import { getSmartAccountClient } from "@/lib/aa/account";
import { loadSessionKey, isSessionExpired } from "@/lib/aa/session-key";
import { sessionKeyValidatorAddress } from "@one-tap/shared-types";

const mockReadContract = vi.mocked(publicClient.readContract);
const mockGetBlock = vi.mocked(publicClient.getBlock);
const mockGetSmartAccountClient = vi.mocked(getSmartAccountClient);
const mockLoadSession = vi.mocked(loadSessionKey);
const mockIsExpired = vi.mocked(isSessionExpired);

const CHAIN_TIMESTAMP = 1_800_000_000n;

const MOCK_SESSION = {
  privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
  address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`,
  validUntil: Math.floor(Date.now() / 1000) + 3600,
  validatorAddress: sessionKeyValidatorAddress[6343],
};

beforeEach(() => {
  vi.clearAllMocks();
  mockReadContract.mockResolvedValue([2000_00000000n, CHAIN_TIMESTAMP] as unknown as never);
  mockGetBlock.mockResolvedValue({ timestamp: CHAIN_TIMESTAMP } as unknown as never);
  mockGetSmartAccountClient.mockResolvedValue({
    sendUserOperation: vi.fn().mockResolvedValue("0xophash"),
  } as never);
  mockLoadSession.mockReturnValue(MOCK_SESSION);
  mockIsExpired.mockReturnValue(false);
});

describe("getCurrentPriceBounds", () => {
  it("returns expectedPrice from oracle", async () => {
    const bounds = await getCurrentPriceBounds();
    expect(bounds.expectedPrice).toBe(2000_00000000n);
  });

  it("sets maxDeviation to 2% of expectedPrice", async () => {
    const bounds = await getCurrentPriceBounds();
    const expected = (2000_00000000n * 200n) / 10_000n;
    expect(bounds.maxDeviation).toBe(expected);
  });

  it("sets deadline to chain block.timestamp + 60s", async () => {
    const bounds = await getCurrentPriceBounds();
    expect(bounds.deadline).toBe(CHAIN_TIMESTAMP + 60n);
  });

  it("retries on transient StalePrice and succeeds", async () => {
    vi.useFakeTimers();
    mockReadContract
      .mockRejectedValueOnce(new Error("StalePrice(1775050362, 1775050375)"))
      .mockResolvedValueOnce([2000_00000000n, CHAIN_TIMESTAMP] as unknown as never);

    const boundsPromise = getCurrentPriceBounds();
    await vi.advanceTimersByTimeAsync(500);
    const bounds = await boundsPromise;

    expect(bounds.expectedPrice).toBe(2000_00000000n);
    expect(mockReadContract).toHaveBeenCalledTimes(2);
    vi.useRealTimers();
  });

  it("throws after all retries exhausted on StalePrice", async () => {
    const staleError = new Error("StalePrice(1, 2)");
    mockReadContract.mockRejectedValue(staleError);
    mockGetBlock.mockResolvedValue({ timestamp: CHAIN_TIMESTAMP } as unknown as never);

    await expect(getCurrentPriceBounds()).rejects.toThrow("StalePrice");
    expect(mockReadContract).toHaveBeenCalledTimes(4); // 1 initial + 3 retries
  });

  it("does not retry non-stale errors", async () => {
    mockReadContract.mockRejectedValueOnce(new Error("ABI encoding error"));

    await expect(getCurrentPriceBounds()).rejects.toThrow("ABI encoding error");
    expect(mockReadContract).toHaveBeenCalledTimes(1);
  });
});

describe("openTrade", () => {
  it("throws if no session key", async () => {
    mockLoadSession.mockReturnValue(null);
    await expect(
      openTrade({ isLong: true, collateral: 1_000_000n, leverage: 5n }),
    ).rejects.toThrow("No active session key");
  });

  it("throws if session expired", async () => {
    mockIsExpired.mockReturnValue(true);
    await expect(
      openTrade({ isLong: true, collateral: 1_000_000n, leverage: 5n }),
    ).rejects.toThrow("Session key expired");
  });

  it("throws if smart account client unavailable", async () => {
    mockGetSmartAccountClient.mockRejectedValueOnce(
      new Error("No stored account — create a passkey account first"),
    );
    await expect(
      openTrade({ isLong: true, collateral: 1_000_000n, leverage: 5n }),
    ).rejects.toThrow("No stored account");
  });

  it("returns opHash on success", async () => {
    const hash = await openTrade({ isLong: true, collateral: 1_000_000n, leverage: 5n });
    expect(hash).toBe("0xophash");
  });
});

describe("closeTrade", () => {
  it("throws if session expired", async () => {
    mockIsExpired.mockReturnValue(true);
    await expect(closeTrade({ positionId: 1n })).rejects.toThrow("Session key expired");
  });

  it("throws if smart account client unavailable", async () => {
    mockGetSmartAccountClient.mockRejectedValueOnce(
      new Error("No stored account — create a passkey account first"),
    );
    await expect(closeTrade({ positionId: 1n })).rejects.toThrow("No stored account");
  });

  it("returns opHash on success", async () => {
    const hash = await closeTrade({ positionId: 1n });
    expect(hash).toBe("0xophash");
  });
});
