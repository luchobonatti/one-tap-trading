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

  useEffect(() => {
    if (!isOpen) reset();
  }, [isOpen, reset]);

  if (!isOpen) return null;

  return (
    <dialog
      open
      className="fixed inset-0 z-[9999] m-0 flex h-full w-full max-w-full items-center justify-center bg-black/70 backdrop-blur-sm"
      aria-labelledby="faucet-modal-title"
      aria-describedby="faucet-modal-description"
    >
      <div className="w-full max-w-sm rounded-2xl border border-[var(--color-neon-cyan)]/20 bg-[var(--color-space-bg)] p-8 shadow-[0_0_40px_var(--color-neon-cyan)/10]">
        <h2
          id="faucet-modal-title"
          className="font-mono text-2xl font-bold text-[var(--color-neon-cyan)]"
        >
          Get 10,000 USDC
        </h2>
        <p
          id="faucet-modal-description"
          className={`mt-2 text-sm text-[var(--color-star-dim)] ${state !== "idle" ? "sr-only" : ""}`}
        >
          Claim free testnet USDC to start trading.
        </p>

        <div className="mt-8">
          {state === "idle" && (
            <button
              type="button"
              onClick={() => void execute()}
              className="w-full rounded-xl border border-[var(--color-neon-cyan)]/60 px-4 py-3 font-mono text-sm font-semibold text-[var(--color-neon-cyan)] shadow-[0_0_16px_var(--color-neon-cyan)/20] transition hover:bg-[var(--color-neon-cyan)]/10 active:scale-95"
            >
              CLAIM
            </button>
          )}

          {state === "loading" && (
            <div className="space-y-3">
              <p className="text-center font-mono text-xs text-[var(--color-star-dim)]">
                Signing with passkey…
              </p>
              <div className="h-px w-full overflow-hidden rounded-full bg-white/5">
                <div className="h-full w-2/3 animate-pulse rounded-full bg-[var(--color-neon-cyan)]/40" />
              </div>
              <button
                type="button"
                disabled
                className="w-full cursor-not-allowed rounded-xl border border-[var(--color-neon-cyan)]/20 px-4 py-3 font-mono text-sm font-semibold text-[var(--color-neon-cyan)]/40"
              >
                CLAIM
              </button>
            </div>
          )}

          {state === "success" && (
            <div className="space-y-2 text-center">
              <div className="font-mono text-3xl text-[var(--color-neon-green)]">✓</div>
              <p className="font-mono text-sm text-[var(--color-neon-green)]">
                10,000 USDC added!
              </p>
            </div>
          )}

          {state === "error" && (
            <div className="space-y-4">
              {error !== undefined && (
                <p className="rounded-lg border border-[var(--color-neon-red)]/20 bg-[var(--color-neon-red)]/5 px-3 py-2 font-mono text-xs text-[var(--color-neon-red)]">
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
                  className="flex-1 rounded-xl border border-[var(--color-neon-cyan)]/60 px-4 py-3 font-mono text-sm font-semibold text-[var(--color-neon-cyan)] shadow-[0_0_16px_var(--color-neon-cyan)/20] transition hover:bg-[var(--color-neon-cyan)]/10 active:scale-95"
                >
                  TRY AGAIN
                </button>
                <button
                  type="button"
                  onClick={onClose}
                  className="flex-1 rounded-xl border border-white/10 px-4 py-3 font-mono text-sm font-semibold text-[var(--color-star-dim)] transition hover:border-white/20 hover:text-[var(--color-ui-text)] active:scale-95"
                >
                  CANCEL
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </dialog>
  );
}
