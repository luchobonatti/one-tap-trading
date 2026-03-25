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

vi.mock("@/lib/aa/signer", () => ({
  buildKernelCallData: vi.fn().mockReturnValue("0xkernel"),
  buildUserOp: vi.fn().mockResolvedValue({ sender: "0x1", nonce: 0n }),
  signUserOp: vi.fn().mockResolvedValue({ sender: "0x1", nonce: 0n, signature: "0xsig" }),
  submitUserOp: vi.fn().mockResolvedValue("0xophash"),
}));

vi.mock("@/lib/aa/session-key", () => ({
  loadSessionKey: vi.fn(),
  isSessionExpired: vi.fn(),
}));

import { publicClient } from "@/lib/aa/client";
import { loadSessionKey, isSessionExpired } from "@/lib/aa/session-key";

const mockReadContract = vi.mocked(publicClient.readContract);
const mockGetBlock = vi.mocked(publicClient.getBlock);
const mockLoadSession = vi.mocked(loadSessionKey);
const mockIsExpired = vi.mocked(isSessionExpired);

const CHAIN_TIMESTAMP = 1_800_000_000n;

const MOCK_SESSION = {
  privateKey: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
  address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`,
  validUntil: Math.floor(Date.now() / 1000) + 3600,
};

beforeEach(() => {
  vi.clearAllMocks();
  mockReadContract.mockResolvedValue([2000_00000000n, CHAIN_TIMESTAMP] as unknown as never);
  mockGetBlock.mockResolvedValue({ timestamp: CHAIN_TIMESTAMP } as unknown as never);
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
});

describe("openTrade", () => {
  it("throws if no session key", async () => {
    mockLoadSession.mockReturnValue(null);
    await expect(
      openTrade({
        isLong: true,
        collateral: 1_000_000n,
        leverage: 5n,
        accountAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      }),
    ).rejects.toThrow("No active session key");
  });

  it("throws if session expired", async () => {
    mockIsExpired.mockReturnValue(true);
    await expect(
      openTrade({
        isLong: true,
        collateral: 1_000_000n,
        leverage: 5n,
        accountAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      }),
    ).rejects.toThrow("Session key expired");
  });

  it("returns opHash on success", async () => {
    const hash = await openTrade({
      isLong: true,
      collateral: 1_000_000n,
      leverage: 5n,
      accountAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    });
    expect(hash).toBe("0xophash");
  });
});

describe("closeTrade", () => {
  it("throws if session expired", async () => {
    mockIsExpired.mockReturnValue(true);
    await expect(
      closeTrade({
        positionId: 1n,
        accountAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      }),
    ).rejects.toThrow("Session key expired");
  });

  it("returns opHash on success", async () => {
    const hash = await closeTrade({
      positionId: 1n,
      accountAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    });
    expect(hash).toBe("0xophash");
  });
});
