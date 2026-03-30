"use client";

import { useEffect, useRef } from "react";
import { useFaucet } from "@/hooks/use-faucet";

type Props = {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
};

export function FaucetModal({ isOpen, onClose, onSuccess }: Props) {
  const { state, error, execute, reset } = useFaucet(onSuccess);
  const timeoutRef = useRef<NodeJS.Timeout | undefined>(undefined);

  // Auto-close on success after 2 seconds
  useEffect(() => {
    if (state === "success") {
      timeoutRef.current = setTimeout(() => {
        onClose();
      }, 2000);
    }
    return () => {
      if (timeoutRef.current !== undefined) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, [state, onClose]);

  if (!isOpen) return null;

  return (
    <dialog
      open
      className="fixed inset-0 m-0 flex h-full w-full max-w-full items-center justify-center bg-black/80 backdrop-blur-sm"
      aria-labelledby="faucet-modal-title"
      aria-describedby="faucet-modal-description"
    >
      <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-8 shadow-2xl">
        <h2
          id="faucet-modal-title"
          className="text-2xl font-bold text-white font-mono"
        >
          Get 10,000 USDC
        </h2>
        {state === "idle" && (
          <p
            id="faucet-modal-description"
            className="mt-2 text-sm text-zinc-400"
          >
            Claim free testnet USDC to start trading.
          </p>
        )}

        <div className="mt-8">
          {state === "idle" && (
            <button
              type="button"
              onClick={() => void execute()}
              className="w-full rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black transition hover:bg-zinc-200 active:scale-95"
            >
              Claim
            </button>
          )}

          {state === "loading" && (
            <div className="space-y-3">
              <div className="text-center text-sm text-zinc-400">
                Signing with passkey…
              </div>
              <div className="h-1 w-full overflow-hidden rounded-full bg-zinc-800">
                <div className="h-full w-2/3 animate-pulse rounded-full bg-white/40" />
              </div>
              <button
                type="button"
                disabled
                className="w-full rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black opacity-50 cursor-not-allowed"
              >
                Claim
              </button>
            </div>
          )}

          {state === "success" && (
            <div className="space-y-3 text-center">
              <div className="text-4xl">✓</div>
              <p className="text-sm text-zinc-300">10,000 USDC added!</p>
            </div>
          )}

          {state === "error" && (
            <div className="space-y-4">
              {error !== undefined && (
                <p className="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-400">
                  {error}
                </p>
              )}
              <div className="flex gap-3">
                <button
                  type="button"
                  onClick={() => {
                    reset();
                    void execute();
                  }}
                  className="flex-1 rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black transition hover:bg-zinc-200 active:scale-95"
                >
                  Try again
                </button>
                <button
                  type="button"
                  onClick={onClose}
                  className="flex-1 rounded-xl border border-white/10 px-4 py-3 text-sm font-semibold text-white transition hover:border-white/30 active:scale-95"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </dialog>
  );
}
