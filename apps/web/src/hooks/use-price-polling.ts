"use client";

import { useRef, useState, useEffect } from "react";
import type { RefObject } from "react";
import { publicClient } from "@/lib/aa/client";
import { priceOracleAbi, priceOracleAddress } from "@one-tap/shared-types";

const PRICE_ORACLE = priceOracleAddress[6343];
const STALE_AFTER_ERRORS = 3;

export type UsePricePollingReturn = {
  priceRef: RefObject<bigint>;
  stale: boolean;
};

export function usePricePolling(interval = 500, enabled = true): UsePricePollingReturn {
  const priceRef = useRef<bigint>(0n);
  const errorCount = useRef(0);
  const [stale, setStale] = useState(false);

  useEffect(() => {
    if (!enabled) return;

    const tick = async () => {
      try {
        const [price] = await publicClient.readContract({
          abi: priceOracleAbi,
          address: PRICE_ORACLE,
          functionName: "getPrice",
        });
        priceRef.current = price;
        if (errorCount.current >= STALE_AFTER_ERRORS) {
          setStale(false);
        }
        errorCount.current = 0;
      } catch {
        errorCount.current += 1;
        if (errorCount.current === STALE_AFTER_ERRORS) {
          setStale(true);
        }
      }
    };

    void tick();
    const id = setInterval(() => void tick(), interval);
    return () => clearInterval(id);
  }, [interval, enabled]);

  return { priceRef, stale };
}
