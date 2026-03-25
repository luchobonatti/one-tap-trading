"use client";

import { useState, useEffect, useCallback } from "react";
import { createPasskeyAccount, loadPasskeyAccount } from "@/lib/aa/account";
import type { Address } from "viem";

export type SmartAccountStatus = "idle" | "loading" | "creating" | "ready" | "error";

export type UseSmartAccountReturn = {
  address: Address | undefined;
  status: SmartAccountStatus;
  error: string | undefined;
  create: () => Promise<void>;
  isReady: boolean;
};

export function useSmartAccount(): UseSmartAccountReturn {
  const [address, setAddress] = useState<Address | undefined>(undefined);
  const [status, setStatus] = useState<SmartAccountStatus>("loading");
  const [error, setError] = useState<string | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    loadPasskeyAccount()
      .then((result) => {
        if (cancelled) return;
        if (result !== null) {
          setAddress(result.address);
          setStatus("ready");
        } else {
          setStatus("idle");
        }
      })
      .catch(() => {
        if (!cancelled) setStatus("idle");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const create = useCallback(async () => {
    setStatus("creating");
    setError(undefined);
    try {
      const result = await createPasskeyAccount("one-tap-user");
      setAddress(result.address);
      setStatus("ready");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Account creation failed");
      setStatus("error");
    }
  }, []);

  return {
    address,
    status,
    error,
    create,
    isReady: status === "ready",
  };
}
