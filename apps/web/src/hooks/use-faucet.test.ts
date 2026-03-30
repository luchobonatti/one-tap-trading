import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useFaucet } from "@/hooks/use-faucet";

vi.mock("@/lib/aa/account", () => ({
  getSmartAccountClient: vi.fn(),
}));

vi.mock("@one-tap/shared-types", () => ({
  mockUsdcAbi: [
    {
      name: "faucet",
      type: "function",
      inputs: [{ name: "amount", type: "uint256" }],
      outputs: [],
      stateMutability: "nonpayable",
    },
  ],
  mockUsdcAddress: {
    6343: "0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB",
  },
}));

import { getSmartAccountClient } from "@/lib/aa/account";

const mockGetSmartAccountClient = vi.mocked(getSmartAccountClient);

const MOCK_CLIENT = {
  account: {
    address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  },
  sendUserOperation: vi.fn(),
  waitForUserOperationReceipt: vi.fn(),
};

beforeEach(() => {
  vi.clearAllMocks();
  mockGetSmartAccountClient.mockResolvedValue(MOCK_CLIENT as any);
});

describe("useFaucet", () => {
  it("starts in idle state", () => {
    const { result } = renderHook(() => useFaucet());
    expect(result.current.state).toBe("idle");
    expect(result.current.error).toBeUndefined();
  });

  it("transitions idle → loading → success on successful execute()", async () => {
    const onSuccess = vi.fn();
    const { result } = renderHook(() => useFaucet(onSuccess));

    MOCK_CLIENT.sendUserOperation.mockResolvedValue("0xophash123");
    MOCK_CLIENT.waitForUserOperationReceipt.mockResolvedValue({});

    await act(async () => {
      await result.current.execute();
    });

    expect(result.current.state).toBe("success");
    expect(result.current.error).toBeUndefined();
    expect(onSuccess).toHaveBeenCalledOnce();
  });

  it("transitions idle → loading → error on rejection", async () => {
    const { result } = renderHook(() => useFaucet());

    MOCK_CLIENT.sendUserOperation.mockRejectedValue(
      new Error("User rejected"),
    );

    await act(async () => {
      await result.current.execute();
    });

    expect(result.current.state).toBe("error");
    expect(result.current.error).toBe("User rejected");
  });

  it("is no-op when execute() called while loading", async () => {
    const { result } = renderHook(() => useFaucet());

    MOCK_CLIENT.sendUserOperation.mockImplementation(
      () =>
        new Promise((resolve) => {
          setTimeout(() => resolve("0xhash"), 100);
        }),
    );
    MOCK_CLIENT.waitForUserOperationReceipt.mockResolvedValue({});

    await act(async () => {
      const promise1 = result.current.execute();
      // Immediately call execute again while first is still loading
      const promise2 = result.current.execute();
      await promise1;
      await promise2;
    });

    // Should only have called sendUserOperation once
    expect(MOCK_CLIENT.sendUserOperation).toHaveBeenCalledOnce();
  });

  it("reset() returns to idle from success state", async () => {
    const { result } = renderHook(() => useFaucet());

    MOCK_CLIENT.sendUserOperation.mockResolvedValue("0xhash");
    MOCK_CLIENT.waitForUserOperationReceipt.mockResolvedValue({});

    await act(async () => {
      await result.current.execute();
    });

    expect(result.current.state).toBe("success");

    act(() => {
      result.current.reset();
    });

    expect(result.current.state).toBe("idle");
    expect(result.current.error).toBeUndefined();
  });

  it("reset() returns to idle from error state", async () => {
    const { result } = renderHook(() => useFaucet());

    MOCK_CLIENT.sendUserOperation.mockRejectedValue(new Error("Failed"));

    await act(async () => {
      await result.current.execute();
    });

    expect(result.current.state).toBe("error");

    act(() => {
      result.current.reset();
    });

    expect(result.current.state).toBe("idle");
    expect(result.current.error).toBeUndefined();
  });

  it("handles non-Error rejection with generic message", async () => {
    const { result } = renderHook(() => useFaucet());

    MOCK_CLIENT.sendUserOperation.mockRejectedValue("Unknown error");

    await act(async () => {
      await result.current.execute();
    });

    expect(result.current.state).toBe("error");
    expect(result.current.error).toBe("Faucet request failed");
  });
});
