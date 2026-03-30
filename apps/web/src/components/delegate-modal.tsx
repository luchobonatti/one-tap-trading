"use client";

import { useState } from "react";
import type { UseSessionKeyReturn } from "@/hooks/use-session-key";

type Props = {
  session: UseSessionKeyReturn;
};

const DEFAULT_SPEND_LIMIT = "100";

export function DelegateModal({ session }: Props) {
  const [spendLimit, setSpendLimit] = useState(DEFAULT_SPEND_LIMIT);
  const { status, error, delegate } = session;

  if (status === "ready") return null;

  return (
    <dialog
      open
      className="fixed inset-0 z-[9999] m-0 flex h-full w-full max-w-full items-center justify-center bg-black/70 backdrop-blur-sm"
      aria-labelledby="delegate-modal-title"
      aria-describedby="delegate-modal-description"
    >
      <div className="w-full max-w-sm rounded-2xl border border-[var(--color-neon-cyan)]/20 bg-[var(--color-space-bg)] p-8 shadow-[0_0_40px_var(--color-neon-cyan)/10]">
        <h2
          id="delegate-modal-title"
          className="font-mono text-2xl font-bold text-[var(--color-neon-cyan)]"
        >
          {status === "expired" ? "Session Expired" : "Enable Trading"}
        </h2>
        <p
          id="delegate-modal-description"
          className="mt-2 text-sm text-[var(--color-star-dim)]"
        >
          {status === "expired"
            ? "Your trading session expired. Renew to continue."
            : "Approve once with your passkey. All trades will sign automatically for 4 hours."}
        </p>

        <div className="mt-6">
          <label
            htmlFor="spend-limit"
            className="block text-xs font-medium uppercase tracking-widest text-[var(--color-star-dim)]"
          >
            Spend limit (USDC)
          </label>
          <input
            id="spend-limit"
            type="number"
            min="1"
            max="10000"
            step="1"
            value={spendLimit}
            onChange={(e) => setSpendLimit(e.target.value)}
            disabled={status === "delegating"}
            className="mt-2 w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 font-mono text-sm text-[var(--color-ui-text)] placeholder-[var(--color-star-dim)] focus:border-[var(--color-neon-cyan)]/40 focus:outline-none focus:ring-1 focus:ring-[var(--color-neon-cyan)]/20 disabled:opacity-50"
          />
        </div>

        <div className="mt-6">
          {(status === "idle" || status === "expired" || status === "error") && (
            <button
              type="button"
              onClick={() => void delegate(spendLimit)}
              className="w-full rounded-xl border border-[var(--color-neon-cyan)]/60 px-4 py-3 font-mono text-sm font-semibold text-[var(--color-neon-cyan)] shadow-[0_0_16px_var(--color-neon-cyan)/20] transition hover:bg-[var(--color-neon-cyan)]/10 active:scale-95"
            >
              {status === "expired" ? "RENEW SESSION" : "ENABLE TRADING"}
            </button>
          )}

          {status === "delegating" && (
            <div className="space-y-3">
              <p className="text-center font-mono text-xs text-[var(--color-star-dim)]">
                Approve with your passkey — this is the last prompt for 4h…
              </p>
              <div className="h-px w-full overflow-hidden rounded-full bg-white/5">
                <div className="h-full w-2/3 animate-pulse rounded-full bg-[var(--color-neon-cyan)]/40" />
              </div>
            </div>
          )}

          {status === "error" && error !== undefined && (
            <p className="mt-3 rounded-lg border border-[var(--color-neon-red)]/20 bg-[var(--color-neon-red)]/5 px-3 py-2 font-mono text-xs text-[var(--color-neon-red)]">
              {error}
            </p>
          )}
        </div>
      </div>
    </dialog>
  );
}
