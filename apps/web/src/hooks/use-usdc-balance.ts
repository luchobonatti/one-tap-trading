"use client";

import { useState, useEffect } from "react";
import { formatUnits, type Address } from "viem";
import { publicClient } from "@/lib/aa/client";
import { mockUsdcAddress } from "@one-tap/shared-types";

const USDC_ADDRESS = (process.env.NEXT_PUBLIC_USDC_ADDRESS as Address | undefined) ?? mockUsdcAddress[6343];

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
    if (address === undefined) {
      setBalance(0n);
      setLoading(false);
      return;
    }

    let cancelled = false;
    let timerId: ReturnType<typeof setTimeout> | undefined;

    const poll = async () => {
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
        if (!cancelled) {
          setLoading(false);
          timerId = setTimeout(() => void poll(), POLL_INTERVAL_MS);
        }
      }
    };

    setLoading(true);
    void poll();

    return () => {
      cancelled = true;
      clearTimeout(timerId);
    };
  }, [address]);

  const formatted = Number(formatUnits(balance, USDC_DECIMALS)).toFixed(2);
  return { balance, formatted, loading };
}
