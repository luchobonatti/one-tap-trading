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
      className="fixed inset-0 m-0 flex h-full w-full max-w-full items-center justify-center bg-black/80 backdrop-blur-sm"
      aria-labelledby="delegate-modal-title"
      aria-describedby="delegate-modal-description"
    >
      <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-8 shadow-2xl">
        <h2
          id="delegate-modal-title"
          className="text-2xl font-bold text-white"
        >
          Enable Trading
        </h2>
        <p
          id="delegate-modal-description"
          className="mt-2 text-sm text-zinc-400"
        >
          {status === "expired"
            ? "Your trading session expired. Renew to continue."
            : "Approve once with your passkey. All trades will sign automatically for 4 hours."}
        </p>

        <div className="mt-6">
          <label
            htmlFor="spend-limit"
            className="block text-xs font-medium text-zinc-400"
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
            className="mt-1 w-full rounded-lg border border-white/10 bg-zinc-800 px-3 py-2 text-sm text-white placeholder-zinc-600 focus:outline-none focus:ring-1 focus:ring-white/30 disabled:opacity-50"
          />
        </div>

        <div className="mt-6">
          {(status === "idle" || status === "expired" || status === "error") && (
            <button
              type="button"
              onClick={() => void delegate(spendLimit)}
              className="w-full rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black transition hover:bg-zinc-200 active:scale-95"
            >
              {status === "expired" ? "Renew Session" : "Enable Trading"}
            </button>
          )}

          {status === "delegating" && (
            <div className="space-y-3">
              <div className="text-center text-sm text-zinc-400">
                Approve with your passkey — this is the last prompt for 4h…
              </div>
              <div className="h-1 w-full overflow-hidden rounded-full bg-zinc-800">
                <div className="h-full w-2/3 animate-pulse rounded-full bg-white/40" />
              </div>
            </div>
          )}

          {status === "error" && error !== undefined && (
            <p className="mt-3 rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-400">
              {error}
            </p>
          )}
        </div>
      </div>
    </dialog>
  );
}
