"use client";

import { useState, useEffect, useCallback } from "react";
import {
  delegateSessionKey,
  loadSessionKey,
  hasSessionKey,
  isSessionExpired,
  clearSessionKey,
  sessionExpiresAt,
} from "@/lib/aa/session-key";

export type SessionKeyStatus =
  | "idle"
  | "delegating"
  | "ready"
  | "expired"
  | "error";

export type UseSessionKeyReturn = {
  status: SessionKeyStatus;
  error: string | undefined;
  expiresAt: Date | undefined;
  delegate: (spendLimitUsdc: string) => Promise<void>;
  revoke: () => void;
  isReady: boolean;
};

export function useSessionKey(isAccountReady: boolean): UseSessionKeyReturn {
  const [status, setStatus] = useState<SessionKeyStatus>("idle");
  const [error, setError] = useState<string | undefined>(undefined);
  const [expiresAt, setExpiresAt] = useState<Date | undefined>(undefined);

  useEffect(() => {
    if (!isAccountReady) return;
    if (!hasSessionKey()) {
      setStatus("idle");
      setExpiresAt(undefined);
      setError(undefined);
      return;
    }
    const session = loadSessionKey();
    if (session === null) {
      setStatus("idle");
      setExpiresAt(undefined);
      setError(undefined);
      return;
    }
    if (isSessionExpired(session)) {
      setStatus("expired");
      setExpiresAt(sessionExpiresAt(session));
    } else {
      setStatus("ready");
      setExpiresAt(sessionExpiresAt(session));
    }
  }, [isAccountReady]);

  const delegate = useCallback(async (spendLimitUsdc: string) => {
    setStatus("delegating");
    setError(undefined);
    try {
      await delegateSessionKey(spendLimitUsdc);
      const session = loadSessionKey();
      if (session === null) {
        setError("Session key not found after delegation. Please try again.");
        setStatus("error");
        setExpiresAt(undefined);
        return;
      }
      setStatus("ready");
      setExpiresAt(sessionExpiresAt(session));
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Session delegation failed",
      );
      setStatus("error");
    }
  }, []);

  const revoke = useCallback(() => {
    clearSessionKey();
    setStatus("idle");
    setExpiresAt(undefined);
    setError(undefined);
  }, []);

  return {
    status,
    error,
    expiresAt,
    delegate,
    revoke,
    isReady: status === "ready",
  };
}
