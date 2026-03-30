"use client";

import { useState, useCallback, useRef } from "react";
import { encodeFunctionData, parseUnits } from "viem";
import { mockUsdcAbi, mockUsdcAddress } from "@one-tap/shared-types";
import { getSmartAccountClient } from "@/lib/aa/account";

type FaucetState = "idle" | "loading" | "success" | "error";

export type UseFaucetReturn = {
  state: FaucetState;
  error: string | undefined;
  execute: () => Promise<void>;
  reset: () => void;
};

const FAUCET_AMOUNT = parseUnits("10000", 6);

export function useFaucet(onSuccess?: () => void): UseFaucetReturn {
  const [state, setState] = useState<FaucetState>("idle");
  const [error, setError] = useState<string | undefined>(undefined);
  const isLoadingRef = useRef(false);

  const execute = useCallback(async () => {
    // Guard: if already loading, no-op
    if (isLoadingRef.current) {
      return;
    }

    isLoadingRef.current = true;
    setState("loading");
    setError(undefined);

    try {
      const client = await getSmartAccountClient();

      const callData = encodeFunctionData({
        abi: mockUsdcAbi,
        functionName: "faucet",
        args: [FAUCET_AMOUNT],
      });

      const opHash = await client.sendUserOperation({
        calls: [
          {
            to: mockUsdcAddress[6343],
            data: callData,
            value: 0n,
          },
        ],
      });

      await client.waitForUserOperationReceipt({ hash: opHash });

      setState("success");
      onSuccess?.();
    } catch (err) {
      const errorMessage =
        err instanceof Error ? err.message : "Faucet request failed";
      setError(errorMessage);
      setState("error");
    } finally {
      isLoadingRef.current = false;
    }
  }, [onSuccess]);

  const reset = useCallback(() => {
    setState("idle");
    setError(undefined);
  }, []);

  return {
    state,
    error,
    execute,
    reset,
  };
}
