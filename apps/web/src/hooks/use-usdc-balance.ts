"use client";

import { useState, useEffect } from "react";
import type { Address } from "viem";
import { publicClient } from "@/lib/aa/client";

const USDC_ADDRESS = (
  process.env.NEXT_PUBLIC_USDC_ADDRESS ?? "0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB"
) as Address;

const USDC_DECIMALS = 6;
const POLL_INTERVAL_MS = 5000;

const BALANCE_OF_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export type UseUsdcBalanceReturn = {
  balance: bigint;
  formatted: string;
  loading: boolean;
};

export function useUsdcBalance(address: Address | undefined): UseUsdcBalanceReturn {
  const [balance, setBalance] = useState(0n);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (address === undefined) return;

    let cancelled = false;

    const fetchBalance = async () => {
      try {
        const result = await publicClient.readContract({
          abi: BALANCE_OF_ABI,
          address: USDC_ADDRESS,
          functionName: "balanceOf",
          args: [address],
        });
        if (!cancelled) setBalance(result);
      } catch (err) {
        console.error("Failed to fetch USDC balance:", err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    setLoading(true);
    void fetchBalance();
    const id = setInterval(() => void fetchBalance(), POLL_INTERVAL_MS);

    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [address]);

  const formatted = (Number(balance) / 10 ** USDC_DECIMALS).toFixed(2);
  return { balance, formatted, loading };
}
