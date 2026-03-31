"use client";

import { useState, useCallback } from "react";
import type { Address, Hex } from "viem";
import { openTrade, waitForOp } from "@/lib/trading/submit";

export type TradeStatus = "idle" | "pending" | "confirmed" | "failed";

export type UseTradeReturn = {
  status: TradeStatus;
  pendingOpHash: Hex | undefined;
  error: string | undefined;
  openPosition: (isLong: boolean, leverage: bigint) => Promise<void>;
  reset: () => void;
};

const DEFAULT_COLLATERAL = 1_000_000n;

export function useTrade(accountAddress: Address | undefined): UseTradeReturn {
  const [status, setStatus] = useState<TradeStatus>("idle");
  const [pendingOpHash, setPendingOpHash] = useState<Hex | undefined>(undefined);
  const [error, setError] = useState<string | undefined>(undefined);

  const openPosition = useCallback(
    async (isLong: boolean, leverage: bigint) => {
      if (accountAddress === undefined) {
        setError("Smart account not ready");
        setStatus("failed");
        return;
      }

      setStatus("pending");
      setPendingOpHash(undefined);
      setError(undefined);

      try {
        const opHash = await openTrade({
          isLong,
          collateral: DEFAULT_COLLATERAL,
          leverage,
        });
        setPendingOpHash(opHash);

        await waitForOp(opHash);
        setStatus("confirmed");
      } catch (err) {
        setError(err instanceof Error ? err.message : "Trade failed");
        setStatus("failed");
      }
    },
    [accountAddress],
  );

  const reset = useCallback(() => {
    setStatus("idle");
    setPendingOpHash(undefined);
    setError(undefined);
  }, []);

  return { status, pendingOpHash, error, openPosition, reset };
}
